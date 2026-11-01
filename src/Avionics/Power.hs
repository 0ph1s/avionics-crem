{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-operator-whitespace-ext-conflict #-}

-- ============================================================================
-- PowerFSM — subsistema de energia (bateria), com estado e topologia próprios
-- ----------------------------------------------------------------------------
-- Máquina independente da de aviônica. Ela só se encontra com a outra na
-- composição (Avionics.Compose). A bateria desce um nível por `Drain` e sobe
-- um por `Recharge`; não existe aresta Charged -> Critical.
-- ============================================================================
module Avionics.Power
  ( PowerVertex (..)
  , SPowerVertex (..)
  , PowerTopology
  , powerTopology
  , sPowerTopology
  , PowerEvent (..)
  , PowerReport (..)
  , powerAction
  , powerBase
  , powerMachine
  ) where

import Crem.BaseMachine
import Crem.Render.RenderableVertices (RenderableVertices (..))
import Crem.StateMachine
import Crem.Topology
import Data.Singletons.Base.TH

$( singletons
    [d|
      data PowerVertex = Charged | Low | Critical
        deriving (Show, Eq)

      powerTopology :: Topology PowerVertex
      powerTopology =
        Topology
          [ (Charged, [Low])
          , (Low, [Charged, Critical])
          , (Critical, [Low])
          ]
      |]
 )

instance RenderableVertices PowerVertex where
  vertices = [Charged, Low, Critical]

-- | Eventos de energia: consumo e recarga.
--
-- `ShedLoad` (acrescentado para o simulador, Avionics.Sim): corte de cargas
-- não essenciais numa emergência. Só tem efeito com a bateria em `Critical`,
-- que passa a `Low`; nos demais níveis não muda o vértice. Usa apenas arestas
-- que já existiam na topologia.
data PowerEvent = Drain | Recharge | ShedLoad
  deriving (Show, Eq)

-- | Relato do nível de bateria após o evento.
data PowerReport = ReportOk | ReportLow | ReportCritical
  deriving (Show, Eq)

powerAction
  :: Applicative m
  => SPowerVertex v
  -> PowerEvent
  -> ActionResult m PowerTopology SPowerVertex v PowerReport
powerAction SCharged  Drain    = pureResult ReportLow SLow
powerAction SCharged  Recharge = pureResult ReportOk SCharged
powerAction SLow      Drain    = pureResult ReportCritical SCritical
powerAction SLow      Recharge = pureResult ReportOk SCharged
powerAction SCritical Drain    = pureResult ReportCritical SCritical
powerAction SCritical Recharge = pureResult ReportLow SLow
powerAction SCharged  ShedLoad = pureResult ReportOk SCharged
powerAction SLow      ShedLoad = pureResult ReportLow SLow
powerAction SCritical ShedLoad = pureResult ReportLow SLow

powerBase :: SPowerVertex v -> BaseMachine PowerTopology PowerEvent PowerReport
powerBase s =
  BaseMachineT
    { initialState = InitialState s
    , action = powerAction
    }

powerMachine :: SPowerVertex v -> StateMachine PowerEvent PowerReport
powerMachine s = Basic (powerBase s)
