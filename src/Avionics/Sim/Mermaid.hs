-- ============================================================================
-- SIMULADOR — Exportação do traço como diagrama Mermaid (sequenceDiagram)
-- ----------------------------------------------------------------------------
-- Função pura que devolve o texto. Quem grava em arquivo é o executável.
--
-- Convenções do desenho:
--   * seta cheia  (->>)  : evento entregue a uma máquina;
--   * seta tracejada (-->>) : saída da máquina, com o vértice em que ficou;
--   * em malha fechada a telemetria vai ao Ambiente; em malha aberta, ao Operador;
--   * "Note over Amb" marca o instante em que o ambiente RETÉM um evento.
-- O `Beat` do relógio não é desenhado (só aparece como o "tick N").
--
-- Cuidado de sintaxe: em mensagens do Mermaid, ';' e '#' quebram o parser;
-- nenhum texto gerado aqui os contém.
-- ============================================================================
module Avionics.Sim.Mermaid
  ( sequenceDiagram
  , marker
  ) where

import Avionics.Sim.Mission (MissionVertex (..))
import Avionics.Sim.Observe (Observation (..))
import Avionics.Sim.Scenario (SimInit (..))
import Avionics.Sim.Trace
import Data.List (mapAccumL)

-- | Primeira linha de todo arquivo gerado; o executável só sobrescreve
-- arquivos que começam com ela.
marker :: String
marker = "%% gerado por avionics-sim (Avionics.Sim.Mermaid)"

-- | Diagrama de sequência de um traço. O primeiro argumento é um comentário
-- descritivo (nome do cenário).
sequenceDiagram :: String -> Trace -> String
sequenceDiagram label t =
  unlines $
    [ marker
    , "%% cenário: " ++ label
    , "sequenceDiagram"
    , "  participant Op as Operador"
    , "  participant Amb as Ambiente"
    , "  participant Av as Avionica"
    , "  participant Pw as Energia"
    , "  Note over Op,Pw: estado inicial Av=" ++ show (simInitAvionics (trInit t))
        ++ " Pw=" ++ show (simInitPower (trInit t))
    ]
      ++ concat (snd (mapAccumL tickLines Standby (trTicks t)))

tickLines :: MissionVertex -> TraceStep -> (MissionVertex, [String])
tickLines held tk =
  let (held', ls) = mapAccumL stepLines held (tsSteps tk)
   in (held', ("  Note over Op,Pw: tick " ++ show (tsTick tk)) : concat ls)

stepLines :: MissionVertex -> StepRecord -> (MissionVertex, [String])
stepLines held s =
  (held', avLines ++ pwLines ++ holdLines)
  where
    closedLoop = maybe False (const True) (srMission s)
    sender = case srOrigin s of
      FromLoop -> "Amb"
      FromClock -> "Amb"
      FromOperator -> "Op"
    listener = if closedLoop then "Amb" else "Op"
    av = srAv s
    pw = srPow s
    avLines = case (obsInput av, obsOutput av) of
      (Just e, Just o) ->
        [ "  " ++ sender ++ "->>Av: " ++ show e
        , "  Av-->>" ++ listener ++ ": " ++ show o ++ ", Av=" ++ show (obsVertex av)
        ]
      (_, _) -> []
    pwLines = case (obsInput pw, obsOutput pw) of
      (Just e, Just r) ->
        [ "  " ++ sender ++ "->>Pw: " ++ show e
        , "  Pw-->>" ++ listener ++ ": " ++ show r ++ ", Pw=" ++ show (obsVertex pw)
        ]
      (_, _) -> []
    (held', holdLines) = case srMission s of
      Nothing -> (held, [])
      Just m
        | obsVertex m /= held && obsVertex m /= Standby ->
            (obsVertex m, ["  Note over Amb: retém (" ++ show (obsVertex m) ++ ")"])
        | otherwise -> (obsVertex m, [])
