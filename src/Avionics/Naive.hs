-- ============================================================================
-- SEÇÃO 1 — FSM ingênua: ADTs e pattern matching exaustivo
-- ----------------------------------------------------------------------------
-- Aqui a máquina é apenas dados e funções puras. Os tipos AvState e AvEvent
-- são "ingênuos" de propósito: nada no tipo diz quais transições são
-- legítimas; só a exaustividade do pattern matching é verificada.
--
-- Nomes: os construtores repetem os dos vértices do CREM (Avionics.Crem), mas
-- vivem em outro módulo; Main os importa qualificados.
--
-- Base teórica:
--   * Milewski (2020), cap. 5: um tipo soma é o coproduto de seus construtores.
--   * Milewski (2020), cap. 9: `State -> Event -> State` é a forma curried de
--     `(State, Event) -> State` (objeto exponencial).
--   * Hutton (2016), cap. 3 (tipos) e cap. 4 (definição de funções por casos).
--   * Malakhovski & Shalyto: FSM como função de transição sobre ADTs.
-- ============================================================================
module Avionics.Naive
  ( AvState (..)
  , AvEvent (..)
  , Output (..)
  , transition
  , outputOf
  , runMealy
  ) where

import Data.List (mapAccumL)

-- | Conjunto Q de estados do UAV.
data AvState
  = Grounded
  | InFlight
  | EmergencyLanding
  | Shutdown
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Alfabeto Σ de eventos externos.
data AvEvent
  = TakeoffSignal
  | CriticalBattery
  | LandedSignal
  | SystemCutoff
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Saída emitida a cada transição (telemetria). `MsgIgnored` marca o
-- evento que não provoca mudança de estado.
data Output
  = MsgTakeoff
  | MsgEmergency
  | MsgLanded
  | MsgShutdown
  | MsgIgnored
  deriving (Show, Eq)

-- | Função de transição δ : Q × Σ → Q, com os 4 × 4 = 16 pares escritos um a
-- um, sem wildcard. Com `-Wall -Werror=incomplete-patterns` (ver o .cabal),
-- esquecer qualquer par é erro de compilação.
--
-- Os quatro pares que mudam de estado são as arestas da topologia; os
-- demais são no-ops (o estado fica igual) e estão escritos caso a caso.
transition :: AvState -> AvEvent -> AvState
transition Grounded         TakeoffSignal   = InFlight
transition Grounded         CriticalBattery = Grounded
transition Grounded         LandedSignal    = Grounded
transition Grounded         SystemCutoff    = Shutdown
transition InFlight         TakeoffSignal   = InFlight
transition InFlight         CriticalBattery = EmergencyLanding
transition InFlight         LandedSignal    = InFlight
transition InFlight         SystemCutoff    = InFlight
transition EmergencyLanding TakeoffSignal   = EmergencyLanding
transition EmergencyLanding CriticalBattery = EmergencyLanding
transition EmergencyLanding LandedSignal    = Grounded
transition EmergencyLanding SystemCutoff    = EmergencyLanding
transition Shutdown         TakeoffSignal   = Shutdown
transition Shutdown         CriticalBattery = Shutdown
transition Shutdown         LandedSignal    = Shutdown
transition Shutdown         SystemCutoff    = Shutdown

-- | Função de saída λ : Q × Σ → Output (máquina de Mealy), também com os
-- 16 pares explícitos.
outputOf :: AvState -> AvEvent -> Output
outputOf Grounded         TakeoffSignal   = MsgTakeoff
outputOf Grounded         CriticalBattery = MsgIgnored
outputOf Grounded         LandedSignal    = MsgIgnored
outputOf Grounded         SystemCutoff    = MsgShutdown
outputOf InFlight         TakeoffSignal   = MsgIgnored
outputOf InFlight         CriticalBattery = MsgEmergency
outputOf InFlight         LandedSignal    = MsgIgnored
outputOf InFlight         SystemCutoff    = MsgIgnored
outputOf EmergencyLanding TakeoffSignal   = MsgIgnored
outputOf EmergencyLanding CriticalBattery = MsgIgnored
outputOf EmergencyLanding LandedSignal    = MsgLanded
outputOf EmergencyLanding SystemCutoff    = MsgIgnored
outputOf Shutdown         TakeoffSignal   = MsgIgnored
outputOf Shutdown         CriticalBattery = MsgIgnored
outputOf Shutdown         LandedSignal    = MsgIgnored
outputOf Shutdown         SystemCutoff    = MsgIgnored

-- | Execução de uma lista de eventos sem mônada: a máquina de Mealy
-- `(Q, Σ) -> (Q, Output)` é um passo de `mapAccumL`, que carrega o estado
-- como acumulador e coleta as saídas. Serve de referência para comparar com
-- a versão State Monad (Avionics.StateMonad.runEvents): a saída por transição
-- não exige mônada.
runMealy :: AvState -> [AvEvent] -> (AvState, [Output])
runMealy = mapAccumL step
  where
    step q e = (transition q e, outputOf q e)
