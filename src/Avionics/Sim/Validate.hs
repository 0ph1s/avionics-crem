{-# LANGUAGE DataKinds #-}

-- ============================================================================
-- SIMULADOR — Validação cruzada contra as implementações existentes
-- ----------------------------------------------------------------------------
-- Dois oráculos que já existiam no projeto:
--   * a FSM ingênua (Avionics.Naive): `transition` e `outputOf`;
--   * a composição `uavSystem` (Avionics.Compose), SEM observação de vértice.
--
-- `replayAgainstNaive` repete, na FSM ingênua, os eventos que a aviônica
-- RECEBEU de fato no traço (inclusive os realimentados pelo ambiente) e exige
-- a mesma saída e o mesmo vértice a cada passo. É isto, e não a lista de
-- comandos do cenário, que se compara em malha fechada: o ambiente injeta
-- eventos extras, então a lista de comandos sozinha não descreve a execução.
-- ============================================================================
module Avionics.Sim.Validate
  ( naiveVertex
  , replayAgainstNaive
  , Sweep (..)
  , sweep
  , uavSystemOutputs
  , simulatedOutputs
  ) where

import qualified Avionics.Compose as Compose
import Avionics.Crem (AvEvent, AvionicsVertex (..), Output, SAvionicsVertex (..))
import qualified Avionics.Naive as N
import Avionics.Power (PowerEvent, PowerReport, SPowerVertex (..))
import Avionics.Sim.Observe (Observation (..))
import Avionics.Sim.Scenario
import Avionics.Sim.Simulate (simulate)
import Avionics.Sim.Trace
import Crem.StateMachine (StateMachineT, run)
import Data.Functor.Identity (Identity (..))

-- | Correspondência entre os vértices do CREM e os estados da FSM ingênua.
naiveVertex :: AvionicsVertex -> N.AvState
naiveVertex Grounded = N.Grounded
naiveVertex InFlight = N.InFlight
naiveVertex EmergencyLanding = N.EmergencyLanding
naiveVertex Shutdown = N.Shutdown

-- | Repete os eventos recebidos pela aviônica na FSM ingênua. `Right ()` se
-- cada passo coincide (saída e vértice); `Left` descreve o primeiro desvio.
replayAgainstNaive :: Trace -> Either String ()
replayAgainstNaive t = go (0 :: Int) (naiveVertex (simInitAvionics (trInit t))) (traceSteps t)
  where
    go _ _ [] = Right ()
    go i q (s : rest) =
      let av = srAv s
          here = naiveVertex (obsVertex av)
       in case obsInput av of
            Nothing
              | obsOutput av /= Nothing -> Left (at i "saída sem evento")
              | here /= q -> Left (at i "vértice mudou sem evento")
              | otherwise -> go (i + 1) q rest
            Just e
              | obsOutput av /= Just (N.outputOf q e) ->
                  Left (at i ("saída " ++ show (obsOutput av) ++ " /= ingênua " ++ show (N.outputOf q e)))
              | here /= N.transition q e ->
                  Left (at i ("vértice " ++ show here ++ " /= ingênua " ++ show (N.transition q e)))
              | otherwise -> go (i + 1) (N.transition q e) rest
    at i msg = "passo " ++ show i ++ ": " ++ msg

-- | Resultado de aplicar uma verificação a muitos cenários.
data Sweep = Sweep
  { swChecked :: Int
  , swFailures :: [(Scenario, String)]
  }

-- | Aplica a verificação a cada cenário, guardando os que falham.
sweep :: (Scenario -> Either String ()) -> [Scenario] -> Sweep
sweep check scenarios =
  Sweep
    { swChecked = length scenarios
    , swFailures = [(sc, msg) | sc <- scenarios, Left msg <- [check sc]]
    }

-- | Saídas da composição ORIGINAL `uavSystem` para uma sequência de pares.
uavSystemOutputs :: [(AvEvent, PowerEvent)] -> [(Output, PowerReport)]
uavSystemOutputs = runIdentity . go (Compose.uavSystem SGrounded SCharged)
  where
    go :: StateMachineT Identity (AvEvent, PowerEvent) (Output, PowerReport) -> [(AvEvent, PowerEvent)] -> Identity [(Output, PowerReport)]
    go _ [] = pure []
    go m (i : is) = do
      (o, m') <- run m i
      os <- go m' is
      pure (o : os)

-- | As mesmas saídas, obtidas pelo simulador (planta observada) com o mesmo
-- estado inicial. Iguais às de `uavSystemOutputs` significa que a observação
-- do vértice não alterou o comportamento.
simulatedOutputs :: [(AvEvent, PowerEvent)] -> [(Output, PowerReport)]
simulatedOutputs inputs =
  [ (o, r)
  | s <- traceSteps (simulate (map (uncurry tick) inputs) defaultInit)
  , Just o <- [obsOutput (srAv s)]
  , Just r <- [obsOutput (srPow s)]
  ]
