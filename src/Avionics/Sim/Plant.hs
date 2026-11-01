{-# LANGUAGE DataKinds #-}

-- ============================================================================
-- SIMULADOR — A planta: aviônica e energia em paralelo, com vértice observado
-- ----------------------------------------------------------------------------
-- `plantStep` é a mesma composição de `Avionics.Compose.uavSystem`
-- (`Parallel` de aviônica e energia), só que cada folha é a versão
-- observada da original. As ações são `avionicsAction` e `powerAction`, as do
-- projeto. Cada máquina aceita `Maybe evento`: `Nothing` a deixa parada.
-- ============================================================================
module Avionics.Sim.Plant
  ( avionicsObserved
  , powerObserved
  , plantStep
  ) where

import Avionics.Crem
import Avionics.Power
import Avionics.Sim.Observe
import Avionics.Sim.Trace (AvObs, PowObs)
import Crem.BaseMachine (BaseMachineT, InitialState (..))
import Crem.StateMachine
import Data.Singletons (fromSing)

-- | `avionicsAction` com o vértice observado.
avionicsObserved
  :: Applicative m
  => SAvionicsVertex v
  -> BaseMachineT m AvionicsTopology (Maybe AvEvent) AvObs
avionicsObserved s = observedMachine fromSing (InitialState s) avionicsAction

-- | `powerAction` com o vértice observado.
powerObserved
  :: Applicative m
  => SPowerVertex v
  -> BaseMachineT m PowerTopology (Maybe PowerEvent) PowObs
powerObserved s = observedMachine fromSing (InitialState s) powerAction

-- | Um passo da planta: as duas máquinas em `Parallel`.
plantStep
  :: Monad m
  => SAvionicsVertex a
  -> SPowerVertex p
  -> StateMachineT m (Maybe AvEvent, Maybe PowerEvent) (AvObs, PowObs)
plantStep a p = Parallel (Basic (avionicsObserved a)) (Basic (powerObserved p))
