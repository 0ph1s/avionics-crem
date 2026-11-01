# avionics-crem

FSM de aviônica de UAV em quatro camadas (projeto PIC, Fatec Rubens Lara).
GHC 9.6.7, cabal 3.12.1.0, `crem` 0.1.0.0, `singletons-base` 3.2.

| Módulo | Seção | Conteúdo |
|---|---|---|
| `src/Avionics/Naive.hs` | 1 | `AvState`, `AvEvent`, `transition` com 16 pares explícitos, `runMealy` |
| `src/Avionics/StateMonad.hs` | 2 | `ST`, `>=>`, provas das leis em comentário, `lawChecks` |
| `src/Avionics/Crem.hs` | 3 | `$(singletons ...)`, topologia, `avionicsAction` com `pureResult` |
| `src/Avionics/Power.hs` | 4 | `PowerFSM` (Charged, Low, Critical) |
| `src/Avionics/Compose.hs` | 4 | `Parallel`, `Sequential`, `Alternative` |
| `src/Avionics/Diagram.hs` | 4 | diagramas Mermaid via `Crem.Render.*` |
| `invalid/InvalidInFlightShutdown.hs` | 4 | transição proibida; NÃO compila |

```bash
cabal build                                              # build principal (não inclui o teste de invalidez)
cabal run avionics-crem                                  # traço, leis, composição; grava output/*.mmd
cabal build invalid-inflight-shutdown --enable-tests     # falha de propósito; ver erro_invalidez_inflight_shutdown.txt
```

## Simulador (malha aberta e fechada)

Simulador puro da composição de FSMs, com ambiente reativo fechado por `Feedback`, validação
cruzada e propriedades sobre o traço. Documentação, decisões e limitações em
[`docs/simulador.md`](docs/simulador.md).

```bash
cabal test avionics-sim-tests    # suíte do simulador (cabal test sem alvo falha por causa do teste de invalidez)
cabal run avionics-sim           # 2 cenários; grava sim_trace_*.mmd em ../../Obsidian/documentation
```

## Estrutura do repositório

```
avionics-crem.cabal      biblioteca, executáveis e test-suites
src/Avionics/            FSM ingênua, State Monad, CREM, energia, composição, diagramas
src/Avionics/Sim/        simulador puro (cenário, traço, planta, ambiente, laço, propriedades)
app/                     executável avionics-crem (seções 1 a 4)
app-sim/                 executável avionics-sim (demonstração do simulador)
test/                    suíte avionics-sim-tests
invalid/                 teste de invalidez (não compila de propósito)
output/                  diagramas e logs gerados pelo executável original
docs/                    documentação do simulador
```

Requisitos: GHC 9.6.7 e cabal 3.12.1.0 (versões usadas nos resultados documentados).
