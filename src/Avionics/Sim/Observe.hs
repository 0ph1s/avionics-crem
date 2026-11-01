{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

-- ============================================================================
-- SIMULADOR — Observação do vértice dentro das ações do CREM
-- ----------------------------------------------------------------------------
-- Problema: em `StateMachineT`, o construtor `Basic` esconde o tipo de estado
-- (é existencial), então do lado de fora de uma máquina composta não há como
-- perguntar "em que vértice você está?". O módulo Render do CREM só enxerga a
-- topologia, não o vértice corrente.
--
-- Solução: `observedMachine` recebe a MESMA função de ação da máquina
-- original (por exemplo `avionicsAction`) e a embrulha. Ao casar o
-- `ActionResult`, o GHC nos entrega o singleton do vértice de destino, que
-- `fromSing` converte em valor. O resultado `ActionResult` é reconstruído com
-- a prova `AllowedTransition` que veio do casamento de padrão, então:
--   * a lógica de transição é a original (nenhuma regra foi reescrita);
--   * uma ação que violasse a topologia continuaria sem compilar.
-- ============================================================================
module Avionics.Sim.Observe
  ( Observation (..)
  , observedMachine
  ) where

import Crem.BaseMachine
import Crem.Topology (Topology)
import Data.Kind (Type)

-- | O que se vê de uma máquina em um passo: o evento recebido (se houve), a
-- saída produzida (se houve) e o vértice em que ela ficou.
data Observation i o v = Observation
  { obsInput :: Maybe i
  , obsOutput :: Maybe o
  , obsVertex :: v
  }
  deriving (Show, Eq)

-- | Máquina base que aceita `Maybe a` como entrada. Com `Nothing` ela fica
-- parada (aresta identidade) e apenas relata o vértice atual; com `Just i`
-- executa a ação original e relata o vértice de destino.
observedMachine
  :: forall m vertex (topology :: Topology vertex) (state :: vertex -> Type) a o v
   . Applicative m
  => (forall w. state w -> v)
  -> InitialState state
  -> (forall w. state w -> a -> ActionResult m topology state w o)
  -> BaseMachineT m topology (Maybe a) (Observation a o v)
observedMachine vertexOf initial act =
  BaseMachineT
    { initialState = initial
    , action = step
    }
  where
    step :: forall w. state w -> Maybe a -> ActionResult m topology state w (Observation a o v)
    step st Nothing = pureResult (Observation Nothing Nothing (vertexOf st)) st
    step st (Just i) = observeResult vertexOf i (act st i)

-- | Acrescenta ao resultado de uma ação o evento recebido e o vértice final.
observeResult
  :: Functor m
  => (forall w. state w -> v)
  -> a
  -> ActionResult m topology state w0 o
  -> ActionResult m topology state w0 (Observation a o v)
observeResult vertexOf i (ActionResult result) =
  ActionResult (fmap (\(o, s') -> (Observation (Just i) (Just o) (vertexOf s'), s')) result)
