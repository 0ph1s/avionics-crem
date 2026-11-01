{-# LANGUAGE DataKinds #-}

-- ============================================================================
-- TESTE DE INVALIDEZ DE TIPAGEM — este módulo NÃO compila, de propósito.
-- ----------------------------------------------------------------------------
-- Tenta a transição proibida InFlight -> Shutdown. A topologia
-- (Avionics.Crem.avionicsTopology) não tem essa aresta, então o GHC não
-- consegue resolver `AllowedTransition AvionicsTopology 'InFlight 'Shutdown`.
--
-- Como obter o erro (fora do build principal):
--   cabal build invalid-inflight-shutdown --enable-tests
-- ============================================================================
module Main (main) where

import Avionics.Crem
import Crem.BaseMachine (ActionResult, pureResult)

invalidInFlightShutdown
  :: Applicative m
  => SAvionicsVertex 'InFlight
  -> AvEvent
  -> ActionResult m AvionicsTopology SAvionicsVertex 'InFlight Output
invalidInFlightShutdown SInFlight _ = pureResult MsgShutdown SShutdown

main :: IO ()
main = putStrLn "inalcançável: o módulo não compila"
