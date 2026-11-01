-- ============================================================================
-- SIMULADOR — Traço de execução
-- ----------------------------------------------------------------------------
-- O traço registra, por tick, a entrada e os PASSOS que as máquinas deram.
-- Um tick pode conter mais de um passo: em malha fechada, o que o ambiente
-- realimenta gera passos extras dentro do mesmo tick (ver `Origin`).
--
-- Cada passo guarda, para cada máquina, o evento recebido, a saída emitida e
-- o vértice em que ela ficou. Como o vértice é registrado a cada passo (e não
-- só ao fim do tick), as propriedades de sequência de vértices são checadas
-- no grão mais fino possível.
-- ============================================================================
module Avionics.Sim.Trace
  ( AvObs
  , PowObs
  , Origin (..)
  , StepRecord (..)
  , TraceStep (..)
  , Trace (..)
  , traceSteps
  , avVertices
  , powVertices
  , misVertices
  , avOutputs
  , significantOutputs
  , finalAvVertex
  , finalPowVertex
  , renderTrace
  ) where

import Avionics.Crem (AvEvent, AvionicsVertex, Output (..))
import Avionics.Power (PowerEvent, PowerReport, PowerVertex)
import Avionics.Sim.Mission (MisObs, MissionVertex (..))
import Avionics.Sim.Observe (Observation (..))
import Avionics.Sim.Scenario (SimInit (..), TickInput (..))
import Data.Maybe (catMaybes)

type AvObs = Observation AvEvent Output AvionicsVertex

type PowObs = Observation PowerEvent PowerReport PowerVertex

-- | De onde veio o estímulo de um passo.
data Origin
  = FromClock
  -- ^ o `Beat` que abre o tick (libera o que o ambiente reteve)
  | FromOperator
  -- ^ entrada externa do cenário
  | FromLoop
  -- ^ estímulo realimentado pelo ambiente dentro do mesmo tick
  deriving (Show, Eq)

-- | Um passo das máquinas folha.
data StepRecord = StepRecord
  { srOrigin :: Origin
  , srAv :: AvObs
  , srPow :: PowObs
  , srMission :: Maybe MisObs
  -- ^ só existe em malha fechada
  }
  deriving (Show, Eq)

-- | Tudo o que aconteceu em um tick.
data TraceStep = TraceStep
  { tsTick :: Int
  , tsInput :: TickInput
  , tsSteps :: [StepRecord]
  }
  deriving (Show, Eq)

-- | Traço completo: estado inicial mais os ticks.
data Trace = Trace
  { trInit :: SimInit
  , trTicks :: [TraceStep]
  }
  deriving (Show, Eq)

-- | Todos os passos, em ordem, de todos os ticks.
traceSteps :: Trace -> [StepRecord]
traceSteps = concatMap tsSteps . trTicks

-- | Sequência de vértices da aviônica: o inicial seguido do vértice após
-- cada passo.
avVertices :: Trace -> [AvionicsVertex]
avVertices t = simInitAvionics (trInit t) : map (obsVertex . srAv) (traceSteps t)

-- | Idem para a energia.
powVertices :: Trace -> [PowerVertex]
powVertices t = simInitPower (trInit t) : map (obsVertex . srPow) (traceSteps t)

-- | Vértices do ambiente (malha fechada): `Standby` no início, depois o
-- vértice após cada passo. Em malha aberta não há ambiente e a lista é
-- só o inicial.
misVertices :: Trace -> [MissionVertex]
misVertices t = Standby : [obsVertex m | Just m <- map srMission (traceSteps t)]

-- | Saídas da aviônica, uma por passo em que ela recebeu evento.
avOutputs :: Trace -> [Output]
avOutputs = catMaybes . map (obsOutput . srAv) . traceSteps

-- | Saídas da aviônica sem `MsgIgnored`.
significantOutputs :: Trace -> [Output]
significantOutputs = filter (/= MsgIgnored) . avOutputs

finalAvVertex :: Trace -> AvionicsVertex
finalAvVertex t = foldl (\_ s -> obsVertex (srAv s)) (simInitAvionics (trInit t)) (traceSteps t)

finalPowVertex :: Trace -> PowerVertex
finalPowVertex t = foldl (\_ s -> obsVertex (srPow s)) (simInitPower (trInit t)) (traceSteps t)

-- ----------------------------------------------------------------------------
-- Impressão textual
-- ----------------------------------------------------------------------------

showMaybe :: Show a => Maybe a -> String
showMaybe = maybe "-" show

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - length s) ' '

originLabel :: Origin -> String
originLabel FromClock = "relogio"
originLabel FromOperator = "operador"
originLabel FromLoop = "laco"

renderStep :: StepRecord -> String
renderStep s =
  "    "
    ++ padRight 9 (originLabel (srOrigin s))
    ++ " av: "
    ++ padRight 15 (showMaybe (obsInput av))
    ++ " -> "
    ++ padRight 12 (showMaybe (obsOutput av))
    ++ " | energia: "
    ++ padRight 9 (showMaybe (obsInput pw))
    ++ " -> "
    ++ padRight 14 (showMaybe (obsOutput pw))
    ++ " => Av="
    ++ padRight 17 (show (obsVertex av))
    ++ " Pw="
    ++ padRight 9 (show (obsVertex pw))
    ++ maybe "" renderMission (srMission s)
  where
    av = srAv s
    pw = srPow s

-- | Parte do passo referente ao ambiente (só em malha fechada).
renderMission :: MisObs -> String
renderMission m =
  " | ambiente: "
    ++ padRight 18 (showMaybe (obsInput m))
    ++ " emite "
    ++ padRight 26 (maybe "[]" show (obsOutput m))
    ++ " => Ms="
    ++ show (obsVertex m)

renderTick :: TraceStep -> [String]
renderTick t =
  ( "tick " ++ show (tsTick t)
      ++ "  entrada: cmd=" ++ showMaybe (tiCommand (tsInput t))
      ++ " energia=" ++ showMaybe (tiPower (tsInput t))
  )
    : map renderStep (tsSteps t)

-- | Traço legível, um bloco por tick.
renderTrace :: Trace -> String
renderTrace t =
  unlines $
    ( "estado inicial: Av=" ++ show (simInitAvionics (trInit t))
        ++ " Pw=" ++ show (simInitPower (trInit t))
    )
      : concatMap renderTick (trTicks t)
      ++ [ "estado final:   Av=" ++ show (finalAvVertex t)
             ++ " Pw=" ++ show (finalPowVertex t)
         , "saídas da aviônica (sem MsgIgnored): " ++ show (significantOutputs t)
         ]
