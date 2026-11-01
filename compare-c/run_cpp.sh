#!/usr/bin/env bash
# Compara o que o compilador de C (clang, o que acompanha o GHC) e o harness exaustivo detectam,
# frente aos mesmos defeitos que foram injetados na versão em Haskell.
# Uso (raiz do pacote):  bash compare-c/run_cpp.sh      Escreve output/comparacao_cpp.md
set -u
cd "$(dirname "$0")/.."
CC=${CC:-/c/ghcup/ghc/$(ghc --numeric-version)/mingw/bin/clang++.exe}
SPEC=spec/domain_rules.txt
W=dist-newstyle/compare-cpp; mkdir -p "$W"; rm -f "$W"/*
FLAGS_A="-std=c++17 -Wall -Wextra"
FLAGS_B="-std=c++17 -Wall -Wextra -Wswitch-enum -Wenum-compare -Wassign-enum"

# saída esperada pela especificação: allow A B E => "A E B"; demais pares: "A E A"
awk '
  $1=="allow" { dest[$2" "$4]=$3 }
  END {
    n=split("Grounded InFlight EmergencyLanding Shutdown",S," ");
    m=split("TakeoffSignal CriticalBattery LandedSignal SystemCutoff",E," ");
    for(i=1;i<=n;i++) for(j=1;j<=m;j++){ k=S[i]" "E[j]; printf "%s %s %s\n", S[i], E[j], (k in dest)?dest[k]:S[i] }
  }' "$SPEC" > "$W/expected.txt"

mutate() { # $1 nome, $2 expressão sed (vazia = nenhuma)
  if [ -z "$2" ]; then cp compare-c/fsm.cpp "$W/$1.cpp"; else sed -e "$2" compare-c/fsm.cpp > "$W/$1.cpp"; fi
  if cmp -s compare-c/fsm.cpp "$W/$1.cpp" && [ "$1" != M0 ]; then echo "mutação $1 não alterou o arquivo" >&2; exit 2; fi
}
mutate M0 ""
mutate M1 '/case event_t::LANDED_SIGNAL:    return state_t::IN_FLIGHT;/d'
mutate M2 '/case event_t::LANDED_SIGNAL:    return state_t::IN_FLIGHT;/c\        default: return s;'
mutate M3 '/case event_t::SYSTEM_CUTOFF:    return state_t::IN_FLIGHT;/s/IN_FLIGHT/SHUTDOWN/'
mutate M4 '0,/case event_t::TAKEOFF_SIGNAL:   return state_t::IN_FLIGHT;/s//case event_t::TAKEOFF_SIGNAL:   return state_t::SHUTDOWN;/'
mutate M5 's/^    switch (s) {$/    if (s == event_t::TAKEOFF_SIGNAL) return state_t::SHUTDOWN;\n    switch (s) {/'
mutate M6 's/^    switch (s) {$/    if (s == state_t::GROUNDED \&\& e == event_t::LANDED_SIGNAL) return static_cast<state_t>(42);\n    switch (s) {/'

names=(M0 M1 M2 M3 M4 M5 M6)
desc=("baseline (sem defeito)" "omite o caso InFlight+LandedSignal (sem default)" "omite o mesmo caso e acrescenta default (curinga)" "transição proibida InFlight+SystemCutoff -> Shutdown" "aresta permitida, destino errado (Grounded+TakeoffSignal -> Shutdown)" "compara estado com constante de evento" "retorna valor fora da enumeração (42)")
rows=""
classify() { # $1 log, $2 código de saída -> "texto|primeira mensagem"
  local warns; warns=$(grep -c "warning:" "$1")
  if [ "$2" -ne 0 ]; then echo "não compila|$(grep -m1 'error:' "$1" | sed 's/^.*error: //')";
  elif [ "$warns" -gt 0 ]; then echo "$warns aviso(s)|$(grep -m1 'warning:' "$1" | sed 's/^.*warning: //')";
  else echo "sem aviso|-"; fi
}
for i in "${!names[@]}"; do
  n=${names[$i]}
  "$CC" $FLAGS_A -o "$W/$n.exe" "$W/$n.cpp" > "$W/$n.logA" 2>&1; ccA=$?
  rA=$(classify "$W/$n.logA" $ccA)
  "$CC" $FLAGS_B -o "$W/${n}b.exe" "$W/$n.cpp" > "$W/$n.logB" 2>&1; ccB=$?
  rB=$(classify "$W/$n.logB" $ccB)
  if [ -x "$W/$n.exe" ]; then
    "$W/$n.exe" | tr -d '\r' > "$W/$n.out"
    if diff -q "$W/$n.out" "$W/expected.txt" > /dev/null; then run="passa"; else run="detecta ($(diff "$W/$n.out" "$W/expected.txt" | grep -c '^<') pares)"; fi
  else run="-"; fi
  printf '%s | %-60s | A: %-12s | B: %-12s | %s
' "$n" "${desc[$i]}" "${rA%%|*}" "${rB%%|*}" "$run"
  rows="$rows| $n | ${desc[$i]} | ${rA%%|*} | ${rB%%|*} | $run | ${rB#*|} |
"
done
{
  echo "# Comparação com a FSM imperativa (C++ com enum class) — o que o compilador e um teste exaustivo detectam"
  echo
  echo "Gerado por \`compare-c/run_cpp.sh\` em $(date +%F). Compilador: $("$CC" --version | head -1). Opções A: \`$FLAGS_A\`. Opções B: \`$FLAGS_B\`."
  echo "Harness: imprime os 16 pares (estado, evento, destino) e compara com \`spec/domain_rules.txt\` (\`diff\`)."
  echo
  echo "| Id | Defeito injetado em \`compare-c/fsm.cpp\` | Compilador, opções A | Compilador, opções B | Harness exaustivo | Primeira mensagem (opções B) |"
  echo "|---|---|---|---|---|---|"
  printf '%s' "$rows"
} > output/comparacao_cpp.md
