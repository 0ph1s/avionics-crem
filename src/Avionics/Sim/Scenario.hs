-- ============================================================================
-- SIMULADOR — Cenário (entrada por tick) e estado inicial
-- ----------------------------------------------------------------------------
-- Um cenário é uma lista de `TickInput`. Cada `TickInput` agrega o que cada
-- máquina folha recebe naquele tick: um evento de comando para a aviônica e/ou
-- um evento de energia para a bateria. `Nothing` significa "nada chegou".
--
-- Módulo puro: sem IO, sem aleatoriedade. As enumerações de entradas
-- (`commandScenarios`, `tickScenarios`) alimentam a validação por
-- enumeração limitada.
-- ============================================================================
module Avionics.Sim.Scenario
  ( TickInput (..)
  , Scenario
  , Signal (..)
  , externalSignals
  , SimInit (..)
  , defaultInit
  , idle
  , command
  , power
  , tick
  , allAvEvents
  , allPowerEvents
  , allTickInputs
  , sequencesUpTo
  , commandScenarios
  , tickScenarios
  , referenceScenario
  , nominalScenario
  , emergencyScenario
  ) where

import Avionics.Crem (AvEvent (..), AvionicsVertex (..))
import Avionics.Power (PowerEvent (..), PowerVertex (..))
import Control.Monad (replicateM)
import Data.Maybe (maybeToList)

-- | O que chega às máquinas folha em um tick.
data TickInput = TickInput
  { tiCommand :: Maybe AvEvent
  -- ^ evento de comando/sensor para a aviônica
  , tiPower :: Maybe PowerEvent
  -- ^ evento de energia para a bateria
  }
  deriving (Show, Eq)

-- | Um cenário é a sequência de entradas, uma por tick.
type Scenario = [TickInput]

-- | Alfabeto de estímulos da malha fechada. `Beat` abre cada tick: é nele
-- que o ambiente libera o que ficou retido no tick anterior. Os demais são
-- um evento para uma das duas máquinas da planta.
data Signal
  = Beat
  | ToAvionics AvEvent
  | ToPower PowerEvent
  deriving (Show, Eq)

-- | Estímulos externos de um tick, na ordem em que são aplicados: o `Beat`,
-- depois o comando, depois a energia.
externalSignals :: TickInput -> [Signal]
externalSignals t =
  Beat : map ToAvionics (maybeToList (tiCommand t)) ++ map ToPower (maybeToList (tiPower t))

-- | Vértices iniciais das máquinas do sistema (valores simples; o simulador
-- os converte em singletons com `withSomeSing`).
data SimInit = SimInit
  { simInitAvionics :: AvionicsVertex
  , simInitPower :: PowerVertex
  }
  deriving (Show, Eq)

-- | Parte do solo com a bateria carregada.
defaultInit :: SimInit
defaultInit = SimInit {simInitAvionics = Grounded, simInitPower = Charged}

-- | Tick sem nenhuma entrada externa.
idle :: TickInput
idle = TickInput {tiCommand = Nothing, tiPower = Nothing}

-- | Tick com apenas um evento de comando.
command :: AvEvent -> TickInput
command e = idle {tiCommand = Just e}

-- | Tick com apenas um evento de energia.
power :: PowerEvent -> TickInput
power e = idle {tiPower = Just e}

-- | Tick com os dois eventos.
tick :: AvEvent -> PowerEvent -> TickInput
tick e p = TickInput {tiCommand = Just e, tiPower = Just p}

allAvEvents :: [AvEvent]
allAvEvents = [TakeoffSignal, CriticalBattery, LandedSignal, SystemCutoff]

allPowerEvents :: [PowerEvent]
allPowerEvents = [Drain, Recharge, ShedLoad]

-- | Todas as entradas possíveis de um tick: (5 opções de comando) x (4 de energia).
allTickInputs :: [TickInput]
allTickInputs =
  [ TickInput c p
  | c <- Nothing : map Just allAvEvents
  , p <- Nothing : map Just allPowerEvents
  ]

-- | Todas as sequências de comprimento 0 a n sobre um alfabeto.
-- Para n = 3 e 4 símbolos dá 1 + 4 + 16 + 64 = 85 (a contagem usada na
-- validação cruzada anterior do projeto).
sequencesUpTo :: Int -> [a] -> [[a]]
sequencesUpTo n alphabet = concat [replicateM k alphabet | k <- [0 .. n]]

-- | Cenários só de comandos (energia ociosa): o espaço comparável com a FSM ingênua.
commandScenarios :: Int -> [Scenario]
commandScenarios n = map (map command) (sequencesUpTo n allAvEvents)

-- | Cenários sobre o alfabeto completo de ticks (15 símbolos).
tickScenarios :: Int -> [Scenario]
tickScenarios n = sequencesUpTo n allTickInputs

-- | Execução de referência (decolagem, bateria crítica, pouso, corte) dada
-- diretamente como comandos, como na validação cruzada original.
referenceScenario :: Scenario
referenceScenario = map command [TakeoffSignal, CriticalBattery, LandedSignal, SystemCutoff]

-- | Voo sem emergência: decola, a bateria cai a `Low` e fica assim.
nominalScenario :: Scenario
nominalScenario = [command TakeoffSignal, idle, power Drain, idle, idle]

-- | Decola e esgota a bateria. Em malha aberta nada acontece com a aviônica;
-- em malha fechada o ambiente encadeia emergência, pouso e corte (um por tick).
emergencyScenario :: Scenario
emergencyScenario =
  [command TakeoffSignal, power Drain, power Drain, idle, idle, idle]
