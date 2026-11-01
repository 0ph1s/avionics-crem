{-# LANGUAGE DataKinds #-}

-- ============================================================================
-- SIMULADOR — Malha fechada com o construtor `Feedback` do CREM
-- ----------------------------------------------------------------------------
-- Assinatura real (Crem.StateMachine, crem-0.1.0.0):
--
--   Feedback :: (Foldable n, Monoid (n a), Monoid (n b))
--            => StateMachineT m a (n b)     -- caminho direto
--            -> StateMachineT m b (n a)     -- caminho de retorno
--            -> StateMachineT m a (n b)
--
-- e a semântica de `run`: roda o caminho direto sobre `a`, passa cada `b`
-- emitido ao caminho de retorno, e reinjeta cada `a` que ele emitir no
-- próprio `Feedback`, recursivamente, até o retorno não emitir mais nada.
-- A saída é tudo o que o caminho direto emitiu em todas as iterações.
--
-- Aqui `n` é a lista, `a` é `Signal` e `b` é `LoopStep` (um passo completo
-- das três máquinas):
--
--   caminho direto:   Signal -> plantas (aviônica || energia) -> ambiente
--   caminho de retorno: o que o ambiente emitiu -> [Signal]  (sem estado)
--
-- O ambiente (FSM de missão) fica no caminho direto, e não no de retorno,
-- por um motivo prático: assim o vértice dele sai junto com os demais na
-- saída do `Feedback`. Se ele estivesse no retorno, a saída dele seria
-- consumida pelo próprio `Feedback` e o vértice não chegaria ao traço.
-- ============================================================================
module Avionics.Sim.Loop
  ( LoopStep (..)
  , classify
  , forwardPath
  , closedLoop
  ) where

import Avionics.Crem
import Avionics.Power
import Avionics.Sim.Mission
import Avionics.Sim.Observe (Observation (..))
import Avionics.Sim.Plant
import Avionics.Sim.Scenario (Signal (..))
import Avionics.Sim.Trace (AvObs, PowObs)
import Crem.StateMachine
import Data.Maybe (fromMaybe)

-- | Um passo completo do caminho direto: o estímulo e o que cada máquina fez.
data LoopStep = LoopStep
  { lsSignal :: Signal
  , lsAv :: AvObs
  , lsPow :: PowObs
  , lsMission :: MisObs
  }
  deriving (Show, Eq)

-- | Como cada `Signal` chega às duas máquinas da planta.
signalToPair :: Signal -> (Maybe AvEvent, Maybe PowerEvent)
signalToPair Beat = (Nothing, Nothing)
signalToPair (ToAvionics e) = (Just e, Nothing)
signalToPair (ToPower e) = (Nothing, Just e)

-- | O que a saída da aviônica interessa ao ambiente.
avCue :: Maybe Output -> Cue
avCue Nothing = CueQuiet
avCue (Just MsgTakeoff) = CueQuiet
avCue (Just MsgEmergency) = CueEmergency
avCue (Just MsgLanded) = CueLanded
avCue (Just MsgShutdown) = CueQuiet
avCue (Just MsgIgnored) = CueQuiet

-- | O que o relato de energia interessa ao ambiente.
powCue :: Maybe PowerReport -> Cue
powCue Nothing = CueQuiet
powCue (Just ReportOk) = CueQuiet
powCue (Just ReportLow) = CueQuiet
powCue (Just ReportCritical) = CueBatteryCritical

-- | Telemetria do passo, na forma que a FSM de missão entende. Cada estímulo
-- move só uma das máquinas da planta, então basta olhar a saída dela.
classify :: Signal -> AvObs -> PowObs -> Cue
classify signal av pw = case signal of
  Beat -> CueBeat
  ToAvionics _event -> avCue (obsOutput av)
  ToPower _event -> powCue (obsOutput pw)

-- | Caminho direto: estímulo -> planta -> telemetria -> ambiente.
forwardPath
  :: Monad m
  => SAvionicsVertex a
  -> SPowerVertex p
  -> SMissionVertex q
  -> StateMachineT m Signal [LoopStep]
forwardPath a p q =
  Sequential
    (stateless (\s -> (signalToPair s, s)))
    ( Sequential
        (Parallel (plantStep a p) (stateless id))
        ( Sequential
            (stateless (\((av, pw), s) -> (Just (classify s av pw), (s, av, pw))))
            ( Sequential
                (Parallel (Basic (missionObserved q)) (stateless id))
                (stateless (\(mo, (s, av, pw)) -> [LoopStep s av pw mo]))
            )
        )
    )

-- | O que o ambiente liberou neste passo, para ser reinjetado.
emitted :: LoopStep -> [Signal]
emitted = fromMaybe [] . obsOutput . lsMission

-- | A malha fechada.
closedLoop
  :: Monad m
  => SAvionicsVertex a
  -> SPowerVertex p
  -> SMissionVertex q
  -> StateMachineT m Signal [LoopStep]
closedLoop a p q = Feedback (forwardPath a p q) (stateless emitted)
