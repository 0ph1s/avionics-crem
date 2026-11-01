-- ============================================================================
-- SIMULADOR — Propriedades sobre o TRAÇO
-- ----------------------------------------------------------------------------
-- Estas funções inspecionam um traço já calculado. Elas NÃO provam nada sobre
-- o sistema: a suíte as aplica a todos os cenários até um comprimento
-- limitado (enumeração limitada). Um traço que viole a propriedade é
-- contraexemplo; ausência de contraexemplo no recorte não é prova.
--
-- Por que ainda vale conferir: o CREM garante cada ARESTA, mas não garante que
-- o simulador (observação, encadeamento de ticks, realimentação) registrou os
-- passos certos. Estas propriedades pegariam, por exemplo, um passo pulado.
-- ============================================================================
module Avionics.Sim.Properties
  ( entries
  , shutdownOnlyAfterGrounded
  , emergencyOnlyFromInFlight
  , releasesMatchRetention
  , shedLoadNeverDrains
  , deterministic
  , prefixCausal
  ) where

import Avionics.Crem (AvEvent (..), AvionicsVertex (..))
import Avionics.Power (PowerEvent (..), PowerVertex (..))
import Avionics.Sim.Mission (MissionVertex (..))
import Avionics.Sim.Observe (Observation (..))
import Avionics.Sim.Scenario
import Avionics.Sim.Trace

-- | Pares (anterior, atual) de vértices consecutivos em que houve mudança.
entries :: Eq a => [a] -> [(a, a)]
entries vs = [(prev, cur) | (prev, cur) <- zip vs (drop 1 vs), prev /= cur]

-- | `Shutdown` só é alcançado imediatamente depois de `Grounded`.
shutdownOnlyAfterGrounded :: Trace -> Bool
shutdownOnlyAfterGrounded t =
  all (\(prev, cur) -> cur /= Shutdown || prev == Grounded) (entries (avVertices t))

-- | Toda entrada em `EmergencyLanding` vem de `InFlight`.
emergencyOnlyFromInFlight :: Trace -> Bool
emergencyOnlyFromInFlight t =
  all (\(prev, cur) -> cur /= EmergencyLanding || prev == InFlight) (entries (avVertices t))

-- | O que o ambiente liberaria se estivesse retendo o vértice dado.
expectedRelease :: MissionVertex -> [Signal]
expectedRelease Standby = []
expectedRelease CriticalHeld = [ToAvionics CriticalBattery]
expectedRelease TouchdownHeld = [ToPower ShedLoad, ToAvionics LandedSignal]
expectedRelease CutoffHeld = [ToAvionics SystemCutoff]

-- | Atraso de exatamente um tick (malha fechada): o `Beat` de cada tick libera
-- o que o ambiente tinha retido ao FIM do tick anterior (e nada, no primeiro
-- tick), e os passos realimentados do tick são exatamente esses sinais.
-- Em malha aberta (sem ambiente) a propriedade vale por vacuidade.
releasesMatchRetention :: Trace -> Bool
releasesMatchRetention t = go Standby (trTicks t)
  where
    go _ [] = True
    go held (tk : rest) =
      let steps = tsSteps tk
          clock = [m | s <- steps, srOrigin s == FromClock, Just m <- [srMission s]]
          fedInputs = concat [fedSignals s | s <- steps, srOrigin s == FromLoop]
          released = concat [r | m <- clock, Just r <- [obsOutput m]]
          held' = foldl (\_ m -> obsVertex m) held [m | s <- steps, Just m <- [srMission s]]
       in (null clock || (released == expectedRelease held && fedInputs == released))
            && go held' rest

-- | Sinais que um passo realimentado entregou às máquinas.
fedSignals :: StepRecord -> [Signal]
fedSignals s =
  [ToAvionics e | Just e <- [obsInput (srAv s)]] ++ [ToPower e | Just e <- [obsInput (srPow s)]]

-- | Nível de bateria como número, para comparar "mais" e "menos" carga.
level :: PowerVertex -> Int
level Critical = 0
level Low = 1
level Charged = 2

-- | `ShedLoad` nunca reduz o nível da bateria: só o sobe de `Critical` para
-- `Low`, e nos demais níveis não muda o vértice.
shedLoadNeverDrains :: Trace -> Bool
shedLoadNeverDrains t = go (simInitPower (trInit t)) (traceSteps t)
  where
    go _ [] = True
    go before (s : rest) =
      let after = obsVertex (srPow s)
          ok = case obsInput (srPow s) of
            Just ShedLoad -> level after >= level before && (before == Critical || after == before)
            Just Drain -> True
            Just Recharge -> True
            Nothing -> True
       in ok && go after rest

-- | Determinismo: a mesma entrada produz o mesmo traço. Em código puro isto é
-- garantido pelo sistema de tipos de Haskell; a verificação existe como
-- regressão (acusaria, por exemplo, uma dependência escondida de estado
-- global se alguém a introduzisse).
deterministic :: (Scenario -> SimInit -> Trace) -> Scenario -> SimInit -> Bool
deterministic sim scenario ini = sim scenario ini == sim scenario ini

-- | Causalidade: o traço de um prefixo do cenário é prefixo do traço do
-- cenário inteiro (o futuro não altera o passado).
prefixCausal :: (Scenario -> SimInit -> Trace) -> Scenario -> SimInit -> Bool
prefixCausal sim scenario ini =
  and
    [ trTicks (sim (take k scenario) ini) == take k full
    | k <- [0 .. length scenario]
    ]
  where
    full = trTicks (sim scenario ini)
