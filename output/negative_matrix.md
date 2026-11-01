# Matriz de rejeição em compilação (16 pares de vértices)

Gerado por `scripts/negative_matrix.sh` em 2026-11-01, com GHC 9.6.7.
Regras esperadas: `spec/domain_rules.txt`. Cada linha foi compilada com `ghc -fno-code`.

| De | Para | Natureza | Esperado | Obtido | Confere |
|---|---|---|---|---|---|
| Grounded | Grounded | identidade | compila | compila | ok |
| Grounded | InFlight | aresta | compila | compila | ok |
| Grounded | EmergencyLanding | proibido | rejeitado | rejeitado | ok |
| Grounded | Shutdown | aresta | compila | compila | ok |
| InFlight | Grounded | proibido | rejeitado | rejeitado | ok |
| InFlight | InFlight | identidade | compila | compila | ok |
| InFlight | EmergencyLanding | aresta | compila | compila | ok |
| InFlight | Shutdown | proibido | rejeitado | rejeitado | ok |
| EmergencyLanding | Grounded | aresta | compila | compila | ok |
| EmergencyLanding | InFlight | proibido | rejeitado | rejeitado | ok |
| EmergencyLanding | EmergencyLanding | identidade | compila | compila | ok |
| EmergencyLanding | Shutdown | proibido | rejeitado | rejeitado | ok |
| Shutdown | Grounded | proibido | rejeitado | rejeitado | ok |
| Shutdown | InFlight | proibido | rejeitado | rejeitado | ok |
| Shutdown | EmergencyLanding | proibido | rejeitado | rejeitado | ok |
| Shutdown | Shutdown | identidade | compila | compila | ok |

Compilaram: 8. Rejeitados: 8. Divergências: 0.

## Erro do GHC nos pares rejeitados (trecho)

- `Grounded → EmergencyLanding`: Could not deduce `Crem.Topology.AllowedTransition (Crem.Topology.Topology '[]) Grounded EmergencyLanding'
- `InFlight → Grounded`: Could not deduce `Crem.Topology.AllowedTransition (Crem.Topology.Topology '[]) InFlight Grounded'
- `InFlight → Shutdown`: Could not deduce `Crem.Topology.AllowedTransition (Crem.Topology.Topology '[]) InFlight Shutdown'
- `EmergencyLanding → InFlight`: Could not deduce `Crem.Topology.AllowedTransition (Crem.Topology.Topology '[]) EmergencyLanding InFlight'
- `EmergencyLanding → Shutdown`: Could not deduce `Crem.Topology.AllowedTransition (Crem.Topology.Topology '[]) EmergencyLanding Shutdown'
- `Shutdown → Grounded`: Could not deduce `Crem.Topology.AllowedTransition (Crem.Topology.Topology '[]) Shutdown Grounded'
- `Shutdown → InFlight`: Could not deduce `Crem.Topology.AllowedTransition (Crem.Topology.Topology '[]) Shutdown InFlight'
- `Shutdown → EmergencyLanding`: Could not deduce `Crem.Topology.AllowedTransition (Crem.Topology.Topology '[]) Shutdown EmergencyLanding'
