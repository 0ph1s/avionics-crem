{-# LANGUAGE OverloadedStrings #-}

-- ============================================================================
-- Diagramas via módulo Render do CREM
-- ----------------------------------------------------------------------------
-- `machineAsGraph` extrai o grafo de uma máquina a partir da topologia das
-- folhas `Basic`; `renderUntypedStateDiagram` o escreve em Mermaid.
-- `renderFlow` desenha, em vez disso, o fluxo entre as máquinas compostas.
-- ============================================================================
module Avionics.Diagram
  ( avionicsDiagram
  , powerDiagram
  , uavProductDiagram
  , coupledFlowDiagram
  ) where

import Avionics.Compose
import Avionics.Crem
import Avionics.Power
import Crem.Render.Render
import Crem.Render.RenderFlow
import Crem.StateMachine
import Data.Functor.Identity (Identity)
import Data.Text (Text)

avionicsDiagram :: Text
avionicsDiagram =
  getText . renderUntypedStateDiagram . machineAsGraph $
    (avionicsMachine SGrounded :: StateMachineT Identity AvEvent Output)

powerDiagram :: Text
powerDiagram =
  getText . renderUntypedStateDiagram . machineAsGraph $
    (powerMachine SCharged :: StateMachineT Identity PowerEvent PowerReport)

-- | Grafo-produto (Parallel): um vértice por par (aviônica, energia).
uavProductDiagram :: Text
uavProductDiagram =
  getText . renderUntypedStateDiagram . machineAsGraph $
    (uavSystem SGrounded SCharged :: StateMachineT Identity (AvEvent, PowerEvent) (Output, PowerReport))

-- | Fluxo da composição acoplada (energia -> tradução -> aviônica).
coupledFlowDiagram :: Either String Text
coupledFlowDiagram =
  fmap (\(m, _, _) -> getText m) $
    renderFlow
      ( BinaryLabel
          (LeafLabel "Power")
          ( BinaryLabel
              (LeafLabel "Translate")
              (BinaryLabel (LeafLabel "Avionics") (LeafLabel "PassThrough"))
          )
      )
      (powerDrivesAvionics SGrounded SCharged :: StateMachineT Identity PowerEvent (Either Output ()))
