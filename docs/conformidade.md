# Conformidade com a especificação do domínio e matriz de rejeição

Fecha uma lacuna da revisão em painel (item 3 do roteiro): os testes anteriores comparavam a FSM
ingênua, as ações do CREM e o ambiente **entre si**, todos escritos a partir da mesma tabela, e a
rejeição em compilação era exercitada em um único par (`InFlight → Shutdown`).

Toolchain: GHC 9.6.7, cabal 3.12.1.0, `crem` 0.1.0.0.

## 1. Especificação separada: `spec/domain_rules.txt`

Escrita a partir do texto dos requisitos (`Example Avionics.md`, "Regras do Domínio"), e não do
código: 4 arestas permitidas, cada uma com o evento que as dispara, e 1 proibição explícita
(`InFlight → Shutdown`). Convenção de mundo fechado: tudo que não é permitido nem identidade é
proibido. Duas decisões que **não** vêm dos requisitos estão marcadas no arquivo: aceitar a aresta
identidade, e dizer que pares (estado, evento) sem regra não mudam o estado.

Limite: a especificação foi escrita pela mesma pessoa que escreveu o código. Ela é um artefato
distinto, derivado de um texto anterior, mas não é um oráculo de terceiros.

## 2. `cabal test avionics-spec-tests` (16 verificações, exaustivas)

O domínio é finito (4 vértices x 4 eventos); nada é amostrado.

| Bloco | O que confronta com a especificação |
|---|---|
| A | arestas do **valor** da topologia do CREM; 8 dos 16 pares são proibidos; `InFlight → Shutdown` está fora |
| B | `Avionics.Naive.transition` nos 16 pares: nenhuma mudança proibida, nenhuma aresta sem evento que a realize |
| C | destino que `avionicsAction` realmente devolve (lido do singleton do `ActionResult`) == `transition` nos 16 pares, e é aresta ou identidade |
| D | cada evento do texto leva exatamente ao destino da especificação (ingênua e CREM); convenção do projeto para pares sem regra |

## 3. `scripts/negative_matrix.sh` (16 compilações)

Para cada par (origem, destino) gera `act SOrigem = pureResult MsgIgnored SDestino` e compila com
`ghc -fno-code`. Esperado: compilam as 4 arestas e as 4 identidades; as outras 8 são rejeitadas com
`Could not deduce AllowedTransition ... Origem Destino` e nenhum outro erro. Resultado
(`output/negative_matrix.md`): **8 compilaram, 8 rejeitados, 0 divergências.** O script sai com
código 0 só nesse caso.

```bash
cabal build
bash scripts/negative_matrix.sh
cabal test avionics-spec-tests
```

## 4. As verificações conseguem falhar? (mutações feitas em 2026-11-01)

Cada defeito foi injetado sozinho e o arquivo restaurado com `git checkout`.

| Defeito injetado | `avionics-spec-tests` | `negative_matrix.sh` |
|---|---|---|
| aresta `InFlight → Shutdown` na topologia **e** na ação do CREM | 4 de 13* falham | 1 divergência (compila onde devia ser rejeitado) |
| só a FSM ingênua: `InFlight` + `SystemCutoff` → `Shutdown` | 3 de 13* falham | passa (não olha a ingênua) |
| CREM: `Grounded` + `TakeoffSignal` → `Shutdown` (aresta permitida, destino errado) | 1 de 13* falha na primeira versão; 2 de 16 com o bloco D | **passa**: o compilador aceita |

\* Contagens da versão anterior do teste (13 verificações, sem o bloco D); só a terceira linha foi repetida com a versão atual (16 verificações). As duas primeiras não foram repetidas.

A terceira linha é o limite da garantia de tipos: **o tipo aceita qualquer destino que seja aresta
da topologia**. Quem pega o erro de associação evento → destino é a especificação com eventos (bloco
D), não o compilador.

## 5. O que isto não cobre

* Garantia por aresta, não por sequência: `InFlight → EmergencyLanding → Grounded → Shutdown`
  continua aceito, e é aresta a aresta conforme a especificação.
* A matriz compila uma ação por par; não prova que nenhuma outra expressão no código viole a
  topologia (isso o compilador faz, por construção, para todo `pureResult`).
* Os pares sem regra no texto (por exemplo, `CriticalBattery` em `Grounded`) seguem a convenção
  do projeto, não os requisitos.

---

# Extensões da revisão (itens 6, 8 e 14 do roteiro)

## 6. Leis de Functor e Applicative para `ST` (`src/Avionics/StateMonad.hs`)

Demonstradas em comentário, no mesmo estilo das leis da mônada (Hutton, 2016, §12.1 e §12.2):
`fmap id = id`, `fmap (g . h) = fmap g . fmap h`, a coincidência de `fmap` e `<*>` com as
definições via `>>=`, e as quatro leis de Applicative a partir delas. A prova de **composição**
está resumida (repete a lei 3 da mônada). `lawChecks` passou de 9 para 17 verificações, todas
aprovadas (`cabal run avionics-crem`).

## 8. Cadeia da bateria e descarte do slot (`cabal test avionics-chain-tests`)

Enumeração em malha fechada sobre o alfabeto reduzido {ocioso, `TakeoffSignal`, `Drain`,
`Recharge`}, N = 8: **87 381 cenários**, ~33 s. Saída completa em `output/cadeia_bateria.txt`.

| Resultado | Valor |
|---|---|
| invariante: toda entrada da bateria em `Critical` com a aviônica em voo leva a `EmergencyLanding` no tick seguinte | **vale nos 87 381** |
| cenários que alcançam `EmergencyLanding` | 22 172 |
| cenários que terminam em `Shutdown` tendo recebido ao menos um `Drain` | 8 160 |
| **achado:** terminam com bateria `Critical`, aviônica em voo e 2 ticks ociosos | 172 (menor: `Drain, Drain, TakeoffSignal, idle, idle`) |
| **achado:** cenários com descarte de telemetria pelo ambiente | 8 726 de 87 381 |

O primeiro achado é uma **lacuna do modelo**, não do CREM: a `Mission` reage à *borda* "a bateria
entrou em `Critical`", e não ao *nível* "a bateria está em `Critical`". Se o UAV decola depois de a
bateria já ter chegado a `Critical` (e a aresta ter sido consumida em solo), nada o leva a
emergência. A `Mission` **não foi alterada**: reagir ao nível é decisão de modelagem do autor.

O descarte ocorre só em `(CutoffHeld | TouchdownHeld, CueBatteryCritical)` (4 144 e 5 651
ocorrências): uma bateria que fica crítica durante a sequência de pouso e corte. Pela estrutura do modelo, o
ambiente só retém esses dois eventos depois de a aviônica ter passado por emergência ou pouso,
então a notícia perdida diz respeito a uma bateria cuja emergência já foi tratada; esse é um
raciocínio sobre o modelo, e o efeito do descarte sobre o estado final não foi medido isoladamente.
Uma nova decolagem com a bateria ainda crítica recai na lacuna borda/nível.

**A invariante consegue falhar?** Mutação: `CriticalHeld` deixa de liberar `CriticalBattery`
(`[ToAvionics CriticalBattery]` vira `[]`). Resultado: a invariante falha com contraexemplo
(`TakeoffSignal, Drain, Drain, idle`) e a cobertura cai a 0 cenários que alcançam
`EmergencyLanding`. Arquivo restaurado com `git checkout`.

Limite: a enumeração usa alfabeto de 4 ticks e N = 8. Cenários com `Recharge` + `Drain` no mesmo
tick, ou com outros comandos, não estão neste recorte (estão, até N = 4, em `avionics-sim-tests`).

## 14. Comparação com a FSM imperativa (`bash compare-c/run.sh`)

A mesma máquina em C (`compare-c/fsm.c`: `enum` e `switch`, o estilo descrito por Malakhovski e
Shalyto), compilada com o clang 14.0.6 que acompanha o GHC. Sete variantes (M0 a M6), cada uma
com um defeito, comparadas com `spec/domain_rules.txt` por um harness exaustivo de 16 pares.
Opções A: `-Wall -Wextra`. Opções B: A + `-Wswitch-enum -Wenum-compare -Wassign-enum`.
Tabela completa em `output/comparacao_c.md`; erros de tipo equivalentes do GHC em
`output/comparacao_haskell_tipos.txt`.

| Defeito | C, opções A | C, opções B | Harness C | Haskell/CREM |
|---|---|---|---|---|
| M1 omite um caso do `switch` | 1 aviso | 1 aviso | passa (o `return` final equivale a no-op) | aviso `-Wincomplete-patterns`; erro com `-Werror=incomplete-patterns` |
| M2 omite o caso e põe `default` | sem aviso | 1 aviso (`-Wswitch-enum`) | passa | sem aviso (o curinga `_` esconde) |
| M3 transição proibida `InFlight → Shutdown` | sem aviso | sem aviso | detecta | **rejeitada na compilação** (matriz, 8 de 8) |
| M4 aresta permitida, destino errado | sem aviso | sem aviso | detecta | aceita pelo compilador; detecta o teste de especificação |
| M5 compara estado com constante de evento | sem aviso | sem aviso | detecta só por acaso (0 == `GROUNDED`) | erro de tipo (`Couldn't match expected type`) |
| M6 valor fora da enumeração (42) | sem aviso | sem aviso | detecta | erro de tipo (`No instance for Num AvState`) |

O que a comparação sustenta, e o que não: (1) o compilador de C com opções adequadas também
avisa de caso omitido; o que o GHC acrescenta, nesse ponto, é que o aviso entra em `-Wall`.
(2) **Para o domínio finito, o teste exaustivo detecta os mesmos defeitos M3 a M6 que o tipo.**
O que o CREM antecipa é a detecção de M3, sem precisar escrever o teste. (3) M4, o destino errado
numa aresta permitida, **nenhum compilador detecta**; exige especificação com eventos. (4) M5 e
M6 são impedidos pelo sistema de tipos de Haskell, sem teste. Uma só máquina, uma só linguagem
de comparação, um só compilador de C: não é um estudo de manutenção nem de esforço.

## 14 (continuação). Segunda linguagem imperativa: C++ com `enum class` (`bash compare-c/run_cpp.sh`)

A mesma máquina em C++ (`compare-c/fsm.cpp`, `enum class` e `switch`), clang++ 14.0.6, as mesmas sete
variantes. Resultados em `output/comparacao_cpp.md`. Diferenças em relação a C: **M5** (comparar
estado com constante de evento) **não compila** em C++ com `enum class`, como em Haskell; **M6** (valor 42
convertido por `static_cast`) compila sem aviso, o que Haskell impede. Para M1 a M4, os resultados
coincidem com os de C (M1 e M2 só com aviso do compilador; M3 e M4 só o teste exaustivo detecta).

## 8 (continuação). Modelo de referência independente e políticas do ambiente (`cabal test avionics-policy-tests`)

`test/SpecPolicy.hs` reimplementa o laço fechado em Haskell comum, sem o CREM (planta pela FSM
ingênua e por uma tabela de energia escrita à parte, classificação da telemetria e ambiente), e o
compara com o simulador do CREM. Em N = 8 no alfabeto reduzido (87 381 cenários), os dois
**coincidem** nos vértices de cada tick e nas saídas (a verificação sai com código de erro se
divergirem). Mutação: `CriticalHeld` liberando `LandedSignal` faz a verificação falhar. Isso
torna o ambiente validado também contra um oráculo que não passa pelo CREM (escrito pela mesma
pessoa, ainda assim).

Com o mesmo modelo, três políticas para o ambiente (saída em `output/politicas_ambiente.txt`):

| Política | Estado final diferente da política do projeto | Terminam com bateria `Critical`, aviônica em voo e 2 ticks ociosos |
|---|---|---|
| `OneSlot` (do projeto: um slot, quem chega primeiro fica) | — | 172 |
| `Queue` (fila sem perda, sem duplicatas) | 0 de 87 381 | 172 |
| `Level` (reage também ao **nível** da bateria a cada `Beat`) | 5 841 de 87 381 | 0 |

Leitura: o descarte do slot, no recorte enumerado, **não altera o estado final** (a fila
não muda nenhum estado final), porque a notícia descartada (`CueBatteryCritical`) chegaria a uma
aviônica que já não está em voo, e `CriticalBattery` é ignorado fora de `InFlight`. A lacuna
borda/nível é outra coisa: só a política `Level` a elimina (172 para 0), ao custo de mudar 5 841
estados finais. **A `Mission` do projeto não foi alterada**; `Level` existe só no modelo de referência.
