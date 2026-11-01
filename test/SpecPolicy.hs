-- ============================================================================
-- Modelo de referência independente do ambiente e comparação de políticas.
-- Rodar com:   cabal test avionics-policy-tests
-- Comprimento máximo N dos cenários: 8 por padrão (outro valor: --test-options=9).
--
-- (1) ORÁCULO INDEPENDENTE. `refRun` reimplementa, em Haskell comum e sem o CREM,
--     o laço fechado: planta (FSM ingênua + tabela de energia), classificação da
--     telemetria e o ambiente `Mission`. Ele é escrito a partir da descrição do
--     laço (docs/simulador.md), não das ações do CREM. Se coincidir com o
--     simulador do CREM em todos os cenários, o ambiente do CREM deixa de ser
--     validado só contra si mesmo. Este é o único item que sai com código de erro.
-- (2) POLÍTICAS. Com o mesmo modelo se comparam três políticas do ambiente:
--       OneSlot : um slot, quem chega primeiro fica (a do projeto);
--       Queue   : fila sem perda (cada tipo de retenção entra uma vez);
--       Level   : um slot, mais a reação ao NÍVEL da bateria (a cada Beat, com o slot
--                 livre, bateria Critical e aviônica em voo, libera CriticalBattery).
--     Os resultados são MEDIDAS ("[achado]"), não invariantes.
-- ============================================================================
module Main (main) where

import Avionics.Crem (AvEvent (..), AvionicsVertex (..), Output (..))
import qualified Avionics.Naive as N
import Avionics.Power (PowerEvent (..), PowerReport (..), PowerVertex (..))
import Avionics.Sim.Observe (Observation (..))
import Avionics.Sim.Scenario
import Avionics.Sim.Simulate
import Avionics.Sim.Trace
import Control.Exception (evaluate)
import Data.List (foldl')
import Data.Maybe (maybeToList)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hSetEncoding, stdout, utf8)

data Policy = OneSlot | Queue | Level deriving (Eq, Show)

data Group = GCrit | GTouch | GCut deriving (Eq, Show)

data M = M
  { mAv :: N.AvState
  , mPow :: PowerVertex
  , mSlot :: [Group]
  , mOuts :: [Output] -- saídas da aviônica diferentes de MsgIgnored, em ordem inversa
  }

data Cue' = Beat' | Crit | Emergency | Landed | Quiet deriving (Eq)

-- | Energia: tabela escrita a partir da descrição (Drain, Recharge e ShedLoad).
powerStep :: PowerVertex -> PowerEvent -> (PowerVertex, PowerReport)
powerStep Charged Drain = (Low, ReportLow)
powerStep Low Drain = (Critical, ReportCritical)
powerStep Critical Drain = (Critical, ReportCritical)
powerStep Charged Recharge = (Charged, ReportOk)
powerStep Low Recharge = (Charged, ReportOk)
powerStep Critical Recharge = (Low, ReportLow)
powerStep Charged ShedLoad = (Charged, ReportOk)
powerStep Low ShedLoad = (Low, ReportLow)
powerStep Critical ShedLoad = (Low, ReportLow)

release :: Group -> [Signal]
release GCrit = [ToAvionics CriticalBattery]
release GTouch = [ToPower ShedLoad, ToAvionics LandedSignal]
release GCut = [ToAvionics SystemCutoff]

process :: Policy -> Signal -> M -> M
process pol sig m0 =
  let (m1, cue) = plant sig m0
      (m2, emitted) = mission pol cue m1
   in foldl' (flip (process pol)) m2 emitted

plant :: Signal -> M -> (M, Cue')
plant Beat m = (m, Beat')
plant (ToAvionics e) m =
  let o = N.outputOf (mAv m) (toN e)
      m' = m {mAv = N.transition (mAv m) (toN e), mOuts = [x | x <- [o], x /= MsgIgnored] ++ mOuts m}
   in (m', avCue o)
plant (ToPower e) m =
  let (p', r) = powerStep (mPow m) e
   in (m {mPow = p'}, if r == ReportCritical then Crit else Quiet)

toN :: AvEvent -> N.AvEvent
toN = id

avCue :: Output -> Cue'
avCue MsgEmergency = Emergency
avCue MsgLanded = Landed
avCue _ = Quiet

mission :: Policy -> Cue' -> M -> (M, [Signal])
mission pol Beat' m =
  let released = concatMap release (mSlot m)
      level = [ToAvionics CriticalBattery | pol == Level, null (mSlot m), mPow m == Critical, mAv m == N.InFlight]
   in (m {mSlot = []}, released ++ level)
mission pol cue m = case groupOf cue of
  Nothing -> (m, [])
  Just g -> case pol of
    Queue -> (if g `elem` mSlot m then m else m {mSlot = mSlot m ++ [g]}, [])
    _ -> (if null (mSlot m) then m {mSlot = [g]} else m, [])

groupOf :: Cue' -> Maybe Group
groupOf Crit = Just GCrit
groupOf Emergency = Just GTouch
groupOf Landed = Just GCut
groupOf _ = Nothing

-- | Roda um cenário e devolve (vértices ao fim de cada tick com o inicial na frente, saídas).
refRun :: Policy -> Scenario -> ([(N.AvState, PowerVertex)], [Output])
refRun pol sc = (snap m0 : reverse ends, reverse (mOuts mEnd))
  where
    m0 = M N.Grounded Charged [] []
    snap m = (mAv m, mPow m)
    (mEnd, ends) = foldl' step (m0, []) sc
    step (m, acc) t =
      let sigs = externalSignals t
          m' = foldl' (flip (process pol)) m sigs
       in (m', snap m' : acc)

fromAvionics :: AvionicsVertex -> N.AvState
fromAvionics Grounded = N.Grounded
fromAvionics InFlight = N.InFlight
fromAvionics EmergencyLanding = N.EmergencyLanding
fromAvionics Shutdown = N.Shutdown

-- | O mesmo resumo, extraído do simulador do CREM.
cremRun :: Scenario -> ([(N.AvState, PowerVertex)], [Output])
cremRun sc =
  let tr = simulateClosed sc defaultInit
      ends = (simInitAvionics (trInit tr), simInitPower (trInit tr)) : map endOf (trTicks tr)
      endOf ts = case reverse (tsSteps ts) of
        s : _ -> (obsVertex (srAv s), obsVertex (srPow s))
        [] -> error "tick sem passos"
   in ([(fromAvionics a, p) | (a, p) <- ends], significantOutputs tr)

stuck :: [(N.AvState, PowerVertex)] -> Bool
stuck ends = case reverse ends of
  (a, p) : _ -> a == N.InFlight && p == Critical
  [] -> False

alphabet :: [TickInput]
alphabet = [idle, command TakeoffSignal, power Drain, power Recharge]

parseN :: [String] -> Int
parseN (a : _) | [(n, "")] <- reads a = n
parseN _ = 8

simplify :: TickInput -> String
simplify t = case (tiCommand t, tiPower t) of
  (Nothing, Nothing) -> "idle"
  (Just c, Nothing) -> show c
  (Nothing, Just p) -> show p
  (Just c, Just p) -> show c ++ "+" ++ show p

main :: IO ()
main = do
  hSetEncoding stdout utf8
  n <- parseN <$> getArgs
  let scenarios = sequencesUpTo n alphabet
      total = length scenarios
  _ <- evaluate total
  putStrLn ("=== Modelo de referência e políticas do ambiente (N = " ++ show n ++ ", " ++ show total ++ " cenários) ===")

  -- (1) oráculo independente
  let diffs = [sc | sc <- scenarios, refRun OneSlot sc /= cremRun sc]
  putStrLn
    ( (if null diffs then "  [ok]    " else "  [FALHA] ")
        ++ "modelo de referência (sem CREM, política OneSlot) == simulador do CREM: vértices a cada tick e saídas"
    )
  mapM_ (\sc -> putStrLn ("            contraexemplo: " ++ show (map simplify sc))) (take 3 diffs)

  -- (2) políticas
  let final pol sc = last (fst (refRun pol sc))
      count p = length (filter p scenarios)
      qDiff = [sc | sc <- scenarios, final Queue sc /= final OneSlot sc]
      lDiff = [sc | sc <- scenarios, final Level sc /= final OneSlot sc]
      shortest xs = foldl' (\a b -> if length b < length a then b else a) (head xs) xs
      idle2 sc = length sc >= 2 && drop (length sc - 2) sc == [idle, idle]
      stuckCount pol = count (\sc -> idle2 sc && stuck (fst (refRun pol sc)))
  putStrLn ("  [achado] cenários em que Queue e OneSlot diferem em algum tick (vértices; as saídas relevantes coincidem nos demais): " ++ show (count (\sc -> fst (refRun Queue sc) /= fst (refRun OneSlot sc))) ++ " de " ++ show total)
  putStrLn ("  [achado] estado final (aviônica, energia) diferente entre Queue e OneSlot: " ++ show (length qDiff) ++ " de " ++ show total)
  if null qDiff then pure () else putStrLn ("           menor exemplo: " ++ show (map simplify (shortest qDiff)))
  putStrLn ("  [achado] estado final diferente entre Level e OneSlot: " ++ show (length lDiff) ++ " de " ++ show total)
  if null lDiff then pure () else putStrLn ("           menor exemplo: " ++ show (map simplify (shortest lDiff)))
  putStrLn "  [achado] cenários que terminam com bateria Critical, aviônica em voo e 2 ticks ociosos:"
  mapM_ (\pol -> putStrLn ("           " ++ show pol ++ ": " ++ show (stuckCount pol))) [OneSlot, Queue, Level]
  _ <- evaluate (length (concatMap maybeToList [Just ()]))
  if null diffs then pure () else exitFailure
