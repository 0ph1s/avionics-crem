#!/usr/bin/env bash
# ============================================================================
# Matriz de rejeição em tempo de compilação: os 16 pares (origem, destino) de vértices.
#
# Para cada par gera um módulo mínimo com
#       act SFrom = pureResult MsgIgnored STo
# e o compila com `ghc -fno-code`. Esperado, segundo spec/domain_rules.txt:
#   - COMPILA   : o par é uma aresta permitida ou a identidade (8 pares);
#   - É REJEITADO: qualquer outro par, com `Could not deduce AllowedTransition ... From To`
#                  e nenhum outro erro (8 pares).
# Sai com código 0 só se os 16 resultados coincidirem com o esperado.
#
# Uso (na raiz do pacote, depois de `cabal build`):   scripts/negative_matrix.sh
# Escreve:  output/negative_matrix.md   (tabela e a primeira linha de cada erro)
#           dist-newstyle/negative-matrix/   (módulos gerados e saídas brutas)
# ============================================================================
set -u
cd "$(dirname "$0")/.."
export LANG=C.UTF-8
SPEC=spec/domain_rules.txt
WORK=dist-newstyle/negative-matrix
OUT=output/negative_matrix.md
VERTS="Grounded InFlight EmergencyLanding Shutdown"

mkdir -p "$WORK" output
rm -f "$WORK"/*.hs "$WORK"/*.log

allowed_in_spec() { # $1 de, $2 para
  awk -v a="$1" -v b="$2" '$1=="allow" && $2==a && $3==b {f=1} END{exit !f}' "$SPEC"
}

expected() {
  if [ "$1" = "$2" ] || allowed_in_spec "$1" "$2"; then echo compila; else echo rejeitado; fi
}

mismatch=0
rows=""
errlines=""
n_comp=0
n_rej=0

for from in $VERTS; do
  for to in $VERTS; do
    mod="M_${from}_${to}"
    file="$WORK/$mod.hs"
    cat > "$file" <<HSEOF
{-# LANGUAGE DataKinds #-}
module $mod where

import Avionics.Crem
import Crem.BaseMachine (ActionResult, pureResult)

act :: Applicative m => SAvionicsVertex '$from -> ActionResult m AvionicsTopology SAvionicsVertex '$from Output
act S$from = pureResult MsgIgnored S$to
HSEOF
    log="$WORK/$mod.log"
    cabal exec -v0 -- ghc -fno-code -package avionics-crem -package crem -package singletons-base "$file" > "$log" 2>&1
    code=$?
    flat=$(tr -s ' \r\n' '   ' < "$log")
    nerr=$(grep -c "error:" "$log")
    exp=$(expected "$from" "$to")
    if [ $code -eq 0 ] && [ "$nerr" -eq 0 ]; then
      got=compila
    elif [ $code -ne 0 ] && [ "$nerr" -eq 1 ] \
         && echo "$flat" | grep -Eq "Could not deduce .?Crem\.Topology\.AllowedTransition.* $from $to'"; then
      got=rejeitado
    else
      got="inesperado(exit=$code,erros=$nerr)"
    fi
    if [ "$got" = "$exp" ]; then ok="ok"; else ok="DIVERGE"; mismatch=$((mismatch+1)); fi
    [ "$got" = compila ] && n_comp=$((n_comp+1))
    [ "$got" = rejeitado ] && n_rej=$((n_rej+1))
    printf '%-17s -> %-17s  esperado=%-9s obtido=%-9s %s\n' "$from" "$to" "$exp" "$got" "$ok"
    kind="aresta"; [ "$from" = "$to" ] && kind="identidade"
    if [ "$exp" = rejeitado ]; then kind="proibido"; fi
    rows="$rows| $from | $to | $kind | $exp | $got | $ok |
"
    if [ "$got" = rejeitado ]; then
      errlines="$errlines- \`$from → $to\`: $(echo "$flat" | grep -Eo "Could not deduce .{0,160}$from $to'" | head -1 | sed 's/  */ /g')
"
    fi
  done
done

{
  echo "# Matriz de rejeição em compilação (16 pares de vértices)"
  echo
  echo "Gerado por \`scripts/negative_matrix.sh\` em $(date +%F), com GHC $(ghc --numeric-version)."
  echo "Regras esperadas: \`spec/domain_rules.txt\`. Cada linha foi compilada com \`ghc -fno-code\`."
  echo
  echo "| De | Para | Natureza | Esperado | Obtido | Confere |"
  echo "|---|---|---|---|---|---|"
  printf '%s' "$rows"
  echo
  echo "Compilaram: $n_comp. Rejeitados: $n_rej. Divergências: $mismatch."
  echo
  echo "## Erro do GHC nos pares rejeitados (trecho)"
  echo
  printf '%s' "$errlines"
} > "$OUT"

echo
echo "compilaram=$n_comp rejeitados=$n_rej divergencias=$mismatch  (relatório: $OUT)"
[ "$mismatch" -eq 0 ] && [ "$n_comp" -eq 8 ] && [ "$n_rej" -eq 8 ]
