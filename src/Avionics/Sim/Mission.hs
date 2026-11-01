{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-operator-whitespace-ext-conflict #-}

-- ============================================================================
-- SIMULADOR — O ambiente reativo: FSM de missão (retém e libera estímulos)
-- ----------------------------------------------------------------------------
-- Papel. Fecha o laço aviônica -> ambiente -> aviônica com UM tick de atraso.
-- O `Feedback` do CREM (Crem.StateMachine) é instantâneo: dentro de um mesmo
-- `run` ele reinjeta o que a segunda máquina emite até ela parar de emitir.
-- Para o efeito aparecer no tick SEGUINTE, esta FSM funciona como um
-- registrador de um slot:
--   * ao ver uma telemetria relevante, ela RETÉM o evento (muda de vértice)
--     e não emite nada;
--   * no `Beat` do tick seguinte, ela LIBERA o evento retido e volta a
--     `Standby`.
--
-- Telemetria -> evento retido (o que o ambiente "faz" com cada notícia):
--   * bateria em nível crítico   -> sensor de bateria crítica (CriticalBattery)
--   * MsgEmergency (descida)     -> corte de cargas (ShedLoad, na energia) e
--                                   toque no solo (LandedSignal), nessa ordem
--   * MsgLanded (pouso)          -> missão encerrada, corte do sistema (SystemCutoff)
--
-- Política de colisão: com o slot ocupado, uma nova telemetria é descartada
-- ("quem chega primeiro fica"). É uma limitação do modelo, documentada em
-- docs/simulador.md.
--
-- Terminação do laço: a FSM só emite quando recebe `CueBeat`, e o único
-- `Beat` vem do cenário (nunca da realimentação). O que ela emite é
-- `ToAvionics e` ou `ToPower e`, cuja telemetria nunca é `CueBeat`. Logo a
-- segunda iteração do `Feedback` não emite nada e o laço para. (`ShedLoad`
-- também não reentra no laço: o relato dele nunca é `ReportCritical`.)
-- ============================================================================
module Avionics.Sim.Mission
  ( MissionVertex (..)
  , SMissionVertex (..)
  , MissionTopology
  , missionTopology
  , sMissionTopology
  , Cue (..)
  , MisObs
  , missionAction
  , missionObserved
  ) where

import Avionics.Crem (AvEvent (..))
import Avionics.Power (PowerEvent (..))
import Avionics.Sim.Observe
import Avionics.Sim.Scenario (Signal (..))
import Crem.BaseMachine
import Crem.Render.RenderableVertices (RenderableVertices (..))
import Crem.Topology
import Data.Singletons.Base.TH

-- Regras do domínio: com o slot livre (Standby) qualquer retenção é possível;
-- uma retenção só termina voltando a Standby. Não há aresta entre retenções.
$( singletons
    [d|
      data MissionVertex
        = Standby
        | CriticalHeld
        | TouchdownHeld
        | CutoffHeld
        deriving (Show, Eq)

      missionTopology :: Topology MissionVertex
      missionTopology =
        Topology
          [ (Standby, [CriticalHeld, TouchdownHeld, CutoffHeld])
          , (CriticalHeld, [Standby])
          , (TouchdownHeld, [Standby])
          , (CutoffHeld, [Standby])
          ]
      |]
 )

instance RenderableVertices MissionVertex where
  vertices = [Standby, CriticalHeld, TouchdownHeld, CutoffHeld]

-- | Telemetria já classificada que a FSM de missão entende.
data Cue
  = CueBeat
  -- ^ início de tick: hora de liberar o que está retido
  | CueBatteryCritical
  | CueEmergency
  | CueLanded
  | CueQuiet
  -- ^ nada que interesse ao ambiente
  deriving (Show, Eq)

-- | Os 4 vértices x 5 telemetrias = 20 casos, escritos um a um, sem curinga.
-- Com o slot ocupado, qualquer telemetria que não seja `CueBeat` mantém o
-- vértice (aresta identidade).
missionAction
  :: Applicative m
  => SMissionVertex v
  -> Cue
  -> ActionResult m MissionTopology SMissionVertex v [Signal]
missionAction SStandby CueBeat                = pureResult [] SStandby
missionAction SStandby CueBatteryCritical     = pureResult [] SCriticalHeld
missionAction SStandby CueEmergency           = pureResult [] STouchdownHeld
missionAction SStandby CueLanded              = pureResult [] SCutoffHeld
missionAction SStandby CueQuiet               = pureResult [] SStandby
missionAction SCriticalHeld CueBeat           = pureResult [ToAvionics CriticalBattery] SStandby
missionAction SCriticalHeld CueBatteryCritical = pureResult [] SCriticalHeld
missionAction SCriticalHeld CueEmergency      = pureResult [] SCriticalHeld
missionAction SCriticalHeld CueLanded         = pureResult [] SCriticalHeld
missionAction SCriticalHeld CueQuiet          = pureResult [] SCriticalHeld
missionAction STouchdownHeld CueBeat          = pureResult [ToPower ShedLoad, ToAvionics LandedSignal] SStandby
missionAction STouchdownHeld CueBatteryCritical = pureResult [] STouchdownHeld
missionAction STouchdownHeld CueEmergency     = pureResult [] STouchdownHeld
missionAction STouchdownHeld CueLanded        = pureResult [] STouchdownHeld
missionAction STouchdownHeld CueQuiet         = pureResult [] STouchdownHeld
missionAction SCutoffHeld CueBeat             = pureResult [ToAvionics SystemCutoff] SStandby
missionAction SCutoffHeld CueBatteryCritical  = pureResult [] SCutoffHeld
missionAction SCutoffHeld CueEmergency        = pureResult [] SCutoffHeld
missionAction SCutoffHeld CueLanded           = pureResult [] SCutoffHeld
missionAction SCutoffHeld CueQuiet            = pureResult [] SCutoffHeld

-- | O que se observa da FSM de missão em um passo.
type MisObs = Observation Cue [Signal] MissionVertex

-- | `missionAction` com o vértice observado.
missionObserved
  :: Applicative m
  => SMissionVertex v
  -> BaseMachineT m MissionTopology (Maybe Cue) MisObs
missionObserved s = observedMachine fromSing (InitialState s) missionAction
