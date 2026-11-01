-- ============================================================================
-- Suíte do simulador. Rodar com:   cabal test avionics-sim-tests
-- Comprimento máximo N das sequências enumeradas: 4 por padrão; outro valor
-- via   cabal test avionics-sim-tests --test-options=5
--
-- Tudo aqui é verificação por ENUMERAÇÃO LIMITADA: nenhum resultado é prova.
-- ============================================================================
module Main (main) where

import Avionics.Crem (AvEvent (..), AvionicsVertex (..), Output (..))
import qualified Avionics.Naive as N
import Avionics.Power (PowerEvent (..), PowerReport (..), PowerVertex (..))
import Avionics.Sim.Mission (Cue (..), MissionVertex (..))
import Avionics.Sim.Observe (Observation (..))
import Avionics.Sim.Properties
import Avionics.Sim.Scenario
import Avionics.Sim.Simulate
import Avionics.Sim.Trace
import Avionics.Sim.Validate
import Control.Exception (evaluate)
import Control.Monad (forM, unless)
import Data.Maybe (listToMaybe)
import GHC.Clock (getMonotonicTime)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hSetEncoding, stdout, utf8)

-- ----------------------------------------------------------------------------
-- Infraestrutura mínima (sem QuickCheck, sem hspec)
-- ----------------------------------------------------------------------------

check :: String -> Bool -> IO Bool
check name ok = do
  putStrLn ((if ok then "  [ok]    " else "  [FALHA] ") ++ name)
  pure ok

timed :: IO a -> IO (a, Double)
timed act = do
  t0 <- getMonotonicTime
  x <- act
  t1 <- getMonotonicTime
  pure (x, t1 - t0)

-- | Verificação sobre um conjunto de cenários: imprime quantos foram
-- enumerados, quanto tempo levou e até 3 contraexemplos.
checkSweep :: String -> Sweep -> IO Bool
checkSweep name sw = do
  (n, secs) <- timed (evaluate (swChecked sw + 0 * length (swFailures sw)))
  let failures = swFailures sw
      ok = null failures
  putStrLn
    ( (if ok then "  [ok]    " else "  [FALHA] ")
        ++ name ++ "  (" ++ show n ++ " cenários, " ++ showSecs secs ++ " s)"
    )
  mapM_ (\(sc, msg) -> putStrLn ("            contraexemplo: " ++ show sc ++ " -> " ++ msg)) (take 3 failures)
  pure ok

-- | Propriedade booleana sobre um conjunto de cenários (também contada e cronometrada).
checkAll :: String -> [Scenario] -> (Scenario -> Bool) -> IO Bool
checkAll name scenarios p =
  checkSweep name (sweep (\sc -> if p sc then Right () else Left "propriedade violada") scenarios)

showSecs :: Double -> String
showSecs s = show (fromIntegral (round (s * 100) :: Int) / 100 :: Double)

parseN :: [String] -> Int
parseN (a : _) | [(n, "")] <- reads a = n
parseN _ = 4

-- ----------------------------------------------------------------------------
-- Traços construídos à mão, só para provar que as verificações não são vacuamente verdadeiras
-- ----------------------------------------------------------------------------

-- | Traço cuja aviônica "salta" pelos vértices dados, sem receber evento.
vertexJumps :: AvionicsVertex -> [AvionicsVertex] -> Trace
vertexJumps v0 vs =
  Trace
    (SimInit v0 Charged)
    [ TraceStep n idle [StepRecord FromOperator (Observation Nothing Nothing v) (Observation Nothing Nothing Charged) Nothing]
    | (n, v) <- zip [0 ..] vs
    ]

-- | Traço em que um `ShedLoad` leva a bateria de Low a Critical.
drainingShed :: Trace
drainingShed =
  Trace
    (SimInit Grounded Low)
    [ TraceStep
        0
        idle
        [ StepRecord
            FromOperator
            (Observation Nothing Nothing Grounded)
            (Observation (Just ShedLoad) (Just ReportCritical) Critical)
            Nothing
        ]
    ]

-- | Traço de um tick em que o `Beat` libera algo que não estava retido.
wrongRelease :: Trace
wrongRelease =
  Trace
    defaultInit
    [ TraceStep
        0
        idle
        [ StepRecord
            FromClock
            (Observation Nothing Nothing Grounded)
            (Observation Nothing Nothing Charged)
            (Just (Observation (Just CueBeat) (Just [ToAvionics LandedSignal]) Standby))
        ]
    ]

-- ----------------------------------------------------------------------------

main :: IO ()
main = do
  hSetEncoding stdout utf8
  n <- parseN <$> getArgs
  let open = simulate
      closed = simulateClosed
      refOuts = [MsgTakeoff, MsgEmergency, MsgLanded, MsgShutdown]
      cmdScs = commandScenarios n
      tickScs = tickScenarios n

  putStrLn "=== A. Execução de referência ==="
  let tRef = open referenceScenario defaultInit
      (qNaive, outsNaive) = N.runMealy N.Grounded [TakeoffSignal, CriticalBattery, LandedSignal, SystemCutoff]
      tEmOpen = open emergencyScenario defaultInit
      tEmClosed = closed emergencyScenario defaultInit
      firstTick p t = listToMaybe [tsTick tk | tk <- trTicks t, any p (tsSteps tk)]
      criticalAt = firstTick (\s -> obsVertex (srPow s) == Critical) tEmClosed
      emergencyAt = firstTick (\s -> obsOutput (srAv s) == Just MsgEmergency) tEmClosed
      shedAt = firstTick (\s -> obsInput (srPow s) == Just ShedLoad) tEmClosed
  a <-
    sequence
      [ check "malha aberta: decolagem, bateria crítica, pouso, corte => [MsgTakeoff, MsgEmergency, MsgLanded, MsgShutdown]"
          (significantOutputs tRef == refOuts)
      , check "malha aberta: estado final da aviônica == Shutdown" (finalAvVertex tRef == Shutdown)
      , check "malha aberta: saídas e estado final == FSM ingênua"
          (avOutputs tRef == outsNaive && naiveVertex (finalAvVertex tRef) == qNaive)
      , check "malha fechada: um Takeoff e dois Drain reproduzem as mesmas 4 saídas"
          (significantOutputs tEmClosed == refOuts)
      , check "malha fechada: estado final da aviônica == Shutdown" (finalAvVertex tEmClosed == Shutdown)
      , check "malha aberta, mesmo cenário: bateria Critical mas a aviônica fica em InFlight (sem realimentação nada acontece)"
          (finalPowVertex tEmOpen == Critical && finalAvVertex tEmOpen == InFlight)
      , check "atraso: MsgEmergency ocorre no tick seguinte àquele em que a bateria chega a Critical"
          (fmap (+ 1) criticalAt == emergencyAt && emergencyAt /= Nothing)
      , check "energia afetada: ShedLoad chega no tick seguinte ao MsgEmergency"
          (fmap (+ 1) emergencyAt == shedAt && shedAt /= Nothing)
      , check "energia afetada: em malha fechada a bateria sai de Critical para Low (e fica Critical em malha aberta)"
          (finalPowVertex tEmClosed == Low && finalPowVertex tEmOpen == Critical)
      ]

  putStrLn ""
  putStrLn ("=== B. Validação cruzada (sequências de até " ++ show n ++ " eventos) ===")
  let crossOpen sc =
        let es = [e | TickInput (Just e) _ <- sc]
            (q, outs) = N.runMealy N.Grounded es
            t = open sc defaultInit
         in if avOutputs t == outs && naiveVertex (finalAvVertex t) == q
              then Right ()
              else Left "saída ou estado final difere da FSM ingênua"
      pairs = [(e, p) | e <- allAvEvents, p <- allPowerEvents]
      pairSeqs = sequencesUpTo n pairs
  (okPairs, secsPairs) <- timed (evaluate (all (\ps -> uavSystemOutputs ps == simulatedOutputs ps) pairSeqs))
  b <-
    sequence
      [ checkSweep "malha aberta == FSM ingênua (saídas e estado final)" (sweep crossOpen cmdScs)
      , checkSweep "malha aberta: repetição passo a passo na FSM ingênua" (sweep (\sc -> replayAgainstNaive (open sc defaultInit)) cmdScs)
      , checkSweep "malha fechada, só comandos: eventos RECEBIDOS repetidos na ingênua" (sweep (\sc -> replayAgainstNaive (closed sc defaultInit)) cmdScs)
      , checkSweep "malha fechada, alfabeto completo de ticks (20 símbolos): idem" (sweep (\sc -> replayAgainstNaive (closed sc defaultInit)) tickScs)
      , check
          ( "observação não altera o comportamento: planta == Compose.uavSystem  ("
              ++ show (length pairSeqs) ++ " sequências, " ++ showSecs secsPairs ++ " s)"
          )
          okPairs
      ]

  putStrLn ""
  putStrLn ("=== C. Propriedades sobre o traço (enumeração limitada, N = " ++ show n ++ ") ===")
  c <-
    fmap concat . forM [("malha aberta", open), ("malha fechada", closed)] $ \(label, sim) ->
      sequence
        [ checkAll (label ++ ": Shutdown só é alcançado logo depois de Grounded") tickScs
            (\sc -> shutdownOnlyAfterGrounded (sim sc defaultInit))
        , checkAll (label ++ ": toda entrada em EmergencyLanding vem de InFlight") tickScs
            (\sc -> emergencyOnlyFromInFlight (sim sc defaultInit))
        , checkAll (label ++ ": ShedLoad nunca reduz o nível da bateria") tickScs
            (\sc -> shedLoadNeverDrains (sim sc defaultInit))
        , checkAll (label ++ ": determinismo (mesma entrada, mesmo traço)") tickScs
            (\sc -> deterministic sim sc defaultInit)
        , checkAll (label ++ ": causalidade (traço do prefixo é prefixo do traço)") (tickScenarios (min n 3))
            (\sc -> prefixCausal sim sc defaultInit)
        ]
  c2 <-
    sequence
      [ checkAll "malha fechada: o Beat libera exatamente o que foi retido no tick anterior" tickScs
          (\sc -> releasesMatchRetention (closed sc defaultInit))
      ]

  putStrLn ""
  putStrLn "=== D. As verificações detectam violações (traços corrompidos à mão) ==="
  d <-
    sequence
      [ check "Shutdown vindo de InFlight é detectado" (not (shutdownOnlyAfterGrounded (vertexJumps InFlight [Shutdown])))
      , check "Shutdown vindo de Grounded é aceito" (shutdownOnlyAfterGrounded (vertexJumps Grounded [Shutdown]))
      , check "EmergencyLanding vindo de Grounded é detectado" (not (emergencyOnlyFromInFlight (vertexJumps Grounded [EmergencyLanding])))
      , check "EmergencyLanding vindo de InFlight é aceito" (emergencyOnlyFromInFlight (vertexJumps InFlight [EmergencyLanding]))
      , check "mudança de vértice sem evento é detectada pela repetição na ingênua"
          (either (const True) (const False) (replayAgainstNaive (vertexJumps Grounded [InFlight])))
      , check "liberação sem retenção prévia é detectada" (not (releasesMatchRetention wrongRelease))
      , check "ShedLoad que descarrega a bateria é detectado" (not (shedLoadNeverDrains drainingShed))
      ]

  putStrLn ""
  let results = concat [a, b, c, c2, d]
      failed = length (filter not results)
  putStrLn (show (length results) ++ " verificações, " ++ show failed ++ " falhas.")
  unless (failed == 0) exitFailure
