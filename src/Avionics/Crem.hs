{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-operator-whitespace-ext-conflict #-}

-- ============================================================================
-- SEÇÃO 3 — A FSM de aviônica com o CREM (segurança de transição em tipos)
-- ----------------------------------------------------------------------------
-- Papéis (Perone, CREM):
--   * `Topology` é um valor que lista, para cada vértice, os vértices de
--     destino permitidos.
--   * `singletons` (via Template Haskell) gera, a partir do tipo de vértices
--     e do valor da topologia, as versões em nível de tipo: os vértices
--     promovidos ('Grounded, 'InFlight, ...), o tipo singleton
--     `SAvionicsVertex v` (um tipo cujo único habitante, para cada v, é o
--     valor correspondente a v) e o tipo `AvionicsTopology`.
--   * `AllowTransition` (GADT) é a prova de que a aresta `from -> to` existe
--     na topologia; `AllowedTransition` é a CLASSE que o GHC resolve sozinho
--     quando a aresta existe. `pureResult` exige essa classe como restrição.
--   * A topologia sempre admite a aresta identidade (`AllowIdentityEdge`):
--     ficar no mesmo vértice é permitido sem constar na lista. Por isso um
--     evento que não deve mudar o estado é escrito devolvendo o mesmo vértice.
-- ============================================================================
module Avionics.Crem
  ( AvionicsVertex (..)
  , SAvionicsVertex (..)
  , AvionicsTopology
  , avionicsTopology
  , sAvionicsTopology
  , avionicsAction
  , avionicsBase
  , avionicsMachine
  , AvEvent (..)
  , Output (..)
  ) where

import Avionics.Naive (AvEvent (..), Output (..))
import Crem.BaseMachine
import Crem.Render.RenderableVertices (RenderableVertices (..))
import Crem.StateMachine
import Crem.Topology
import Data.Singletons.Base.TH

-- O tipo dos vértices e o valor da topologia entram juntos no mesmo bloco TH.
-- Regras do domínio: de Grounded pode-se ir a InFlight ou Shutdown; de
-- InFlight só a EmergencyLanding; de EmergencyLanding só a Grounded. Não há
-- aresta InFlight -> Shutdown.
$( singletons
    [d|
      data AvionicsVertex
        = Grounded
        | InFlight
        | EmergencyLanding
        | Shutdown
        deriving (Show, Eq)

      avionicsTopology :: Topology AvionicsVertex
      avionicsTopology =
        Topology
          [ (Grounded, [InFlight, Shutdown])
          , (InFlight, [EmergencyLanding])
          , (EmergencyLanding, [Grounded])
          ]
      |]
 )

-- | Necessário para desenhar a máquina (módulo Render do CREM).
instance RenderableVertices AvionicsVertex where
  vertices = [Grounded, InFlight, EmergencyLanding, Shutdown]

-- | Ação da FSM. O vértice atual chega como singleton, então o casamento de
-- padrão informa ao GHC em que vértice a máquina está. O segundo argumento de
-- `pureResult` é o vértice de destino; o GHC precisa resolver
-- `AllowedTransition AvionicsTopology origem destino`, e só consegue se a
-- aresta existir (ou for a identidade).
--
-- Os 16 pares (vértice, evento) estão escritos um a um. Eventos que não
-- provocam transição devolvem o mesmo vértice (aresta identidade).
avionicsAction
  :: Applicative m
  => SAvionicsVertex v
  -> AvEvent
  -> ActionResult m AvionicsTopology SAvionicsVertex v Output
avionicsAction SGrounded TakeoffSignal         = pureResult MsgTakeoff SInFlight
avionicsAction SGrounded CriticalBattery       = pureResult MsgIgnored SGrounded
avionicsAction SGrounded LandedSignal          = pureResult MsgIgnored SGrounded
avionicsAction SGrounded SystemCutoff          = pureResult MsgShutdown SShutdown
avionicsAction SInFlight TakeoffSignal         = pureResult MsgIgnored SInFlight
avionicsAction SInFlight CriticalBattery       = pureResult MsgEmergency SEmergencyLanding
avionicsAction SInFlight LandedSignal          = pureResult MsgIgnored SInFlight
avionicsAction SInFlight SystemCutoff          = pureResult MsgIgnored SInFlight
avionicsAction SEmergencyLanding TakeoffSignal   = pureResult MsgIgnored SEmergencyLanding
avionicsAction SEmergencyLanding CriticalBattery = pureResult MsgIgnored SEmergencyLanding
avionicsAction SEmergencyLanding LandedSignal    = pureResult MsgLanded SGrounded
avionicsAction SEmergencyLanding SystemCutoff    = pureResult MsgIgnored SEmergencyLanding
avionicsAction SShutdown TakeoffSignal         = pureResult MsgIgnored SShutdown
avionicsAction SShutdown CriticalBattery       = pureResult MsgIgnored SShutdown
avionicsAction SShutdown LandedSignal          = pureResult MsgIgnored SShutdown
avionicsAction SShutdown SystemCutoff          = pureResult MsgIgnored SShutdown

-- | Máquina base: estado inicial e ação, para qualquer mônada.
avionicsBase :: SAvionicsVertex v -> BaseMachine AvionicsTopology AvEvent Output
avionicsBase s =
  BaseMachineT
    { initialState = InitialState s
    , action = avionicsAction
    }

-- | A máquina base como folha (`Basic`) de uma árvore componível.
avionicsMachine :: SAvionicsVertex v -> StateMachine AvEvent Output
avionicsMachine s = Basic (avionicsBase s)
