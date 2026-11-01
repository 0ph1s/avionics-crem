-- ============================================================================
-- Cadeia da bateria e descarte do registrador de um slot, por enumeração.
-- Rodar com:   cabal test avionics-chain-tests
-- Comprimento máximo N dos cenários: 8 por padrão (outro valor: --test-options=9).
--
-- Fecha duas lacunas da suíte do simulador (N = 4 não alcança a cadeia induzida pela
-- bateria, que exige 6 ticks, e o descarte do slot só era descrito, não medido).
--
-- Alfabeto reduzido de 4 ticks: ocioso, TakeoffSignal, Drain, Recharge. Em N = 8 são
-- 87 381 cenários em malha fechada. Resultados rotulados "[ok]" são invariantes que
-- precisam valer (exit code); os rotulados "[achado]" são MEDIDAS do comportamento
-- do modelo, que não alteram o exit code.
-- ============================================================================
module Main (main) where

import Avionics.Crem (AvEvent (..), AvionicsVertex (..))
import Avionics.Power (PowerEvent (..), PowerVertex (..))
import Avionics.Sim.Mission (Cue (..), MissionVertex (..))
import Avionics.Sim.Observe (Observation (..))
import Avionics.Sim.Scenario
import Avionics.Sim.Simulate
import Avionics.Sim.Trace
import Control.Exception (evaluate)
import Data.List (foldl')
import Data.Maybe (isJust)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hSetEncoding, stdout, utf8)

alphabet :: [TickInput]
alphabet = [idle, command TakeoffSignal, power Drain, power Recharge]

-- | Vértices (aviônica, energia) ao fim de cada tick, com o estado inicial na frente.
tickEnds :: Trace -> [(AvionicsVertex, PowerVertex)]
tickEnds t = (simInitAvionics (trInit t), simInitPower (trInit t)) : map end (trTicks t)
  where
    end ts = case reverse (tsSteps ts) of
      s : _ -> (obsVertex (srAv s), obsVertex (srPow s))
      [] -> error "tick sem passos"

-- | Resposta à bateria crítica: se ao fim do tick t a bateria ENTROU em Critical e a
-- aviônica está em voo, ao fim do tick t+1 (se existir) ela está em EmergencyLanding.
batteryResponseHolds :: Trace -> Bool
batteryResponseHolds t = and [ok i | i <- [1 .. length ends - 2]]
  where
    ends = tickEnds t
    ok i =
      let (_, pPrev) = ends !! (i - 1)
          (a, p) = ends !! i
          (aNext, _) = ends !! (i + 1)
       in not (pPrev /= Critical && p == Critical && a == InFlight) || aNext == EmergencyLanding

-- | Lacuna de nível: o cenário termina com 2 ticks ociosos, a bateria em Critical e a
-- aviônica ainda em voo, ou seja, ninguém reagiu ao ESTADO crítico.
stuckInFlight :: Trace -> Bool
stuckInFlight t = case reverse (tickEnds t) of
  (a, p) : _ -> a == InFlight && p == Critical
  [] -> False

-- | Passos em que o ambiente, ocupado (vértice diferente de Standby), recebeu telemetria
-- relevante e continuou no mesmo vértice: o sinal foi descartado.
drops :: Trace -> [(MissionVertex, Cue)]
drops t =
  [ (before, cue)
  | (before, s) <- zip (misVertices t) (traceSteps t)
  , Just m <- [srMission s]
  , Just cue <- [obsInput m]
  , cue `elem` [CueBatteryCritical, CueEmergency, CueLanded]
  , before /= Standby
  , obsVertex m == before
  ]

parseN :: [String] -> Int
parseN (a : _) | [(n, "")] <- reads a = n
parseN _ = 8

main :: IO ()
main = do
  hSetEncoding stdout utf8
  n <- parseN <$> getArgs
  let scenarios = sequencesUpTo n alphabet
      traces = [(sc, simulateClosed sc defaultInit) | sc <- scenarios]
      total = length scenarios
  _ <- evaluate total
  putStrLn ("=== Cadeia da bateria e descarte do slot (N = " ++ show n ++ ", " ++ show total ++ " cenários, malha fechada) ===")

  -- invariante 1: resposta à entrada em Critical estando em voo
  let viol = [sc | (sc, tr) <- traces, not (batteryResponseHolds tr)]
  putStrLn
    ( (if null viol then "  [ok]    " else "  [FALHA] ")
        ++ "toda entrada da bateria em Critical, com a aviônica em voo, leva a EmergencyLanding no tick seguinte"
    )
  mapM_ (\sc -> putStrLn ("            contraexemplo: " ++ show sc)) (take 3 viol)

  -- cobertura: a cadeia completa (decolagem, 2 Drain, emergência, pouso, corte) foi alcançada?
  let reachedShutdownByBattery =
        length
          [ ()
          | (sc, tr) <- traces
          , finalAvVertex tr == Shutdown
          , any (== Just Drain) (map tiPower sc)
          ]
      reachedEmergency = length [() | (_, tr) <- traces, EmergencyLanding `elem` avVertices tr]
  putStrLn ("  [achado] cenários que alcançam EmergencyLanding: " ++ show reachedEmergency)
  putStrLn ("  [achado] cenários que terminam em Shutdown tendo recebido ao menos um Drain: " ++ show reachedShutdownByBattery)
  let okCoverage = reachedEmergency > 0 && reachedShutdownByBattery > 0
  putStrLn
    ( (if okCoverage then "  [ok]    " else "  [FALHA] ")
        ++ "a enumeração alcança a cadeia completa induzida pela bateria (antes inalcançável com N = 4)"
    )

  -- achado 2: nível versus borda
  let stuck = [sc | (sc, tr) <- traces, length sc >= 2, drop (length sc - 2) sc == [idle, idle], stuckInFlight tr]
  putStrLn ("  [achado] cenários que terminam com bateria Critical e aviônica em voo, sem reação em 2 ticks ociosos: " ++ show (length stuck))
  case stuck of
    [] -> pure ()
    _ -> do
      let shortest = foldl' (\a b -> if length b < length a then b else a) (head stuck) stuck
      putStrLn ("           menor exemplo: " ++ show (map simplify shortest))
      putStrLn "           (o ambiente reage à BORDA 'bateria entrou em Critical', e não ao NÍVEL 'bateria está em Critical')"

  -- achado 3: descarte do slot
  let withDrop = [(sc, drops tr) | (sc, tr) <- traces, not (null (drops tr))]
      kinds = [(v, c) | (_, ds) <- withDrop, (v, c) <- ds]
      count k = length (filter (== k) kinds)
      distinctKinds = foldr (\k acc -> if k `elem` acc then acc else k : acc) [] kinds
  putStrLn ("  [achado] cenários com ao menos um descarte de telemetria pelo ambiente: " ++ show (length withDrop) ++ " de " ++ show total)
  mapM_ (\k -> putStrLn ("           " ++ show k ++ ": " ++ show (count k) ++ " ocorrências")) distinctKinds
  case withDrop of
    [] -> pure ()
    _ -> do
      let (sc, _) = foldl' (\a@(x, _) b@(y, _) -> if length y < length x then b else a) (head withDrop) withDrop
      putStrLn ("           menor exemplo: " ++ show (map simplify sc))

  _ <- evaluate (isJust (Just ()))
  if null viol && okCoverage then pure () else exitFailure

simplify :: TickInput -> String
simplify t = case (tiCommand t, tiPower t) of
  (Nothing, Nothing) -> "idle"
  (Just c, Nothing) -> show c
  (Nothing, Just p) -> show p
  (Just c, Just p) -> show c ++ "+" ++ show p
