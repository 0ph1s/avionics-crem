-- ============================================================================
-- SEÇÃO 4 — Composição real de máquinas com os construtores do CREM
-- ----------------------------------------------------------------------------
-- `StateMachineT` é uma árvore: as folhas são `Basic` (uma máquina base com
-- topologia e estado próprios) e os nós são `Sequential`, `Parallel`,
-- `Alternative`, `Feedback` e `Kleisli`. Cada folha guarda o seu próprio
-- estado; a composição não mistura os vértices de uma com os da outra.
--
-- Duas composições são montadas aqui:
--
--   1. `uavSystem`: `Parallel` de aviônica e energia. Cada máquina recebe a
--      sua entrada e emite a sua saída; não há acoplamento.
--
--   2. `powerDrivesAvionics`: `Sequential`. A saída de energia é traduzida
--      por uma máquina sem estado (`stateless`) em um evento de aviônica, e
--      `Alternative` aplica a aviônica apenas quando há evento (Left) e deixa
--      passar `()` caso contrário (Right). Assim, uma bateria em nível
--      crítico produz `CriticalBattery` na máquina de aviônica.
-- ============================================================================
module Avionics.Compose
  ( uavSystem
  , powerDrivesAvionics
  , toAvionicsEvent
  ) where

import Avionics.Crem
import Avionics.Power
import Crem.StateMachine

-- | Composição em paralelo: entradas e saídas são pares.
uavSystem
  :: SAvionicsVertex a
  -> SPowerVertex p
  -> StateMachine (AvEvent, PowerEvent) (Output, PowerReport)
uavSystem a p = Parallel (avionicsMachine a) (powerMachine p)

-- | Tradução (sem estado) do relato de energia em evento de aviônica.
toAvionicsEvent :: PowerReport -> Either AvEvent ()
toAvionicsEvent ReportCritical = Left CriticalBattery
toAvionicsEvent ReportOk = Right ()
toAvionicsEvent ReportLow = Right ()

-- | Composição em sequência: energia -> tradução -> aviônica.
powerDrivesAvionics
  :: SAvionicsVertex a
  -> SPowerVertex p
  -> StateMachine PowerEvent (Either Output ())
powerDrivesAvionics a p =
  Sequential
    (powerMachine p)
    ( Sequential
        (stateless toAvionicsEvent)
        (Alternative (avionicsMachine a) (stateless id))
    )
