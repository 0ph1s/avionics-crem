# Comparação com a FSM imperativa (C++ com enum class) — o que o compilador e um teste exaustivo detectam

Gerado por `compare-c/run_cpp.sh` em 2026-11-01. Compilador: clang version 14.0.6. Opções A: `-std=c++17 -Wall -Wextra`. Opções B: `-std=c++17 -Wall -Wextra -Wswitch-enum -Wenum-compare -Wassign-enum`.
Harness: imprime os 16 pares (estado, evento, destino) e compara com `spec/domain_rules.txt` (`diff`).

| Id | Defeito injetado em `compare-c/fsm.cpp` | Compilador, opções A | Compilador, opções B | Harness exaustivo | Primeira mensagem (opções B) |
|---|---|---|---|---|---|
| M0 | baseline (sem defeito) | sem aviso | sem aviso | passa | - |
| M1 | omite o caso InFlight+LandedSignal (sem default) | 1 aviso(s) | 1 aviso(s) | passa | enumeration value 'LANDED_SIGNAL' not handled in switch [-Wswitch] |
| M2 | omite o mesmo caso e acrescenta default (curinga) | sem aviso | 1 aviso(s) | passa | enumeration value 'LANDED_SIGNAL' not explicitly handled in switch [-Wswitch-enum] |
| M3 | transição proibida InFlight+SystemCutoff -> Shutdown | sem aviso | sem aviso | detecta (1 pares) | - |
| M4 | aresta permitida, destino errado (Grounded+TakeoffSignal -> Shutdown) | sem aviso | sem aviso | detecta (1 pares) | - |
| M5 | compara estado com constante de evento | não compila | não compila | - | invalid operands to binary expression ('state_t' and 'event_t') |
| M6 | retorna valor fora da enumeração (42) | sem aviso | sem aviso | detecta (1 pares) | - |
