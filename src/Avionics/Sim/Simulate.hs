{-# LANGUAGE DataKinds #-}

-- ============================================================================
-- SIMULADOR — Execução pura de um cenário
-- ----------------------------------------------------------------------------
-- O "estado" que a State Monad do projeto (`ST`) carrega de passo em passo é a
-- própria máquina composta: `ST World ...` consome a máquina de um passo e
-- devolve a máquina do passo seguinte. `mapM` encadeia os passos.
--
-- Duas versões:
--   * `simulate`: malha aberta, cada máquina só recebe o que o cenário manda.
--   * `simulateClosed`: malha fechada, o ambiente realimenta a aviônica com
--     um tick de atraso (ver Avionics.Sim.Mission e Avionics.Sim.Loop).
--
-- Nada aqui faz IO. As máquinas rodam em `Identity`.
-- ============================================================================
module Avionics.Sim.Simulate
  ( simulate
  , simulateClosed
  ) where

import Avionics.Crem (AvionicsVertex)
import Avionics.Power (PowerVertex)
import Avionics.Sim.Loop
import Avionics.Sim.Mission (SMissionVertex (..))
import Avionics.Sim.Plant
import Avionics.Sim.Scenario
import Avionics.Sim.Trace
import Avionics.StateMonad (ST (..))
import Crem.StateMachine
import Data.Functor.Identity (Identity (..))
import Data.Singletons (withSomeSing)

-- ----------------------------------------------------------------------------
-- Malha aberta
-- ----------------------------------------------------------------------------

-- | A planta com entrada agregada por tick.
type OpenWorld = StateMachineT Identity TickInput (AvObs, PowObs)

openWorld :: SimInit -> OpenWorld
openWorld (SimInit av pw) =
  withSomeSing @AvionicsVertex av $ \sa ->
    withSomeSing @PowerVertex pw $ \sp ->
      Sequential (stateless (\t -> (tiCommand t, tiPower t))) (plantStep sa sp)

-- | Um tick em malha aberta: a entrada vai direto às duas máquinas.
openTick :: Int -> TickInput -> ST OpenWorld TraceStep
openTick n input = ST $ \world ->
  let ((av, pw), world') = runIdentity (run world input)
   in (TraceStep n input [StepRecord FromOperator av pw Nothing], world')

-- | Simulação em malha aberta: cada máquina só recebe o que o cenário manda.
simulate :: Scenario -> SimInit -> Trace
simulate scenario ini =
  let (ticks, _final) = runST (mapM (uncurry openTick) (zip [0 ..] scenario)) (openWorld ini)
   in Trace ini ticks

-- ----------------------------------------------------------------------------
-- Malha fechada
-- ----------------------------------------------------------------------------

-- | A malha fechada: estímulo entra, passos completos saem.
type ClosedWorld = StateMachineT Identity Signal [LoopStep]

-- | O ambiente sempre começa em `Standby` (nada retido).
closedWorld :: SimInit -> ClosedWorld
closedWorld (SimInit av pw) =
  withSomeSing @AvionicsVertex av $ \sa ->
    withSomeSing @PowerVertex pw $ \sp ->
      closedLoop sa sp SStandby

-- | De onde veio o estímulo externo.
originOf :: Signal -> Origin
originOf Beat = FromClock
originOf (ToAvionics _event) = FromOperator
originOf (ToPower _event) = FromOperator

toRecord :: Origin -> LoopStep -> StepRecord
toRecord origin s = StepRecord origin (lsAv s) (lsPow s) (Just (lsMission s))

-- | Aplica um estímulo externo. O primeiro passo devolvido é o do próprio
-- estímulo; os demais foram realimentados pelo ambiente.
closedSignal :: Signal -> ST ClosedWorld [StepRecord]
closedSignal signal = ST $ \world ->
  let (steps, world') = runIdentity (run world signal)
      records = case steps of
        [] -> []
        first : fed -> toRecord (originOf signal) first : map (toRecord FromLoop) fed
   in (records, world')

-- | Um tick em malha fechada: `Beat`, depois comando, depois energia.
closedTick :: Int -> TickInput -> ST ClosedWorld TraceStep
closedTick n input = do
  groups <- mapM closedSignal (externalSignals input)
  pure (TraceStep n input (concat groups))

-- | Simulação em malha fechada.
simulateClosed :: Scenario -> SimInit -> Trace
simulateClosed scenario ini =
  let (ticks, _final) = runST (mapM (uncurry closedTick) (zip [0 ..] scenario)) (closedWorld ini)
   in Trace ini ticks
