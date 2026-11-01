/* Mesma FSM de aviônica em C, com enum e switch (estilo imperativo descrito por
 * Malakhovski e Shalyto). Serve de BASE DE COMPARAÇÃO com a versão em Haskell.
 * Imprime os 16 pares (estado, evento, destino) para ser conferido contra
 * spec/domain_rules.txt por compare-c/run.sh. */
#include <stdio.h>

typedef enum { GROUNDED, IN_FLIGHT, EMERGENCY_LANDING, SHUTDOWN } state_t;
typedef enum { TAKEOFF_SIGNAL, CRITICAL_BATTERY, LANDED_SIGNAL, SYSTEM_CUTOFF } event_t;

state_t transition(state_t s, event_t e)
{
    switch (s) {
    case GROUNDED:
        switch (e) {
        case TAKEOFF_SIGNAL:   return IN_FLIGHT;
        case CRITICAL_BATTERY: return GROUNDED;
        case LANDED_SIGNAL:    return GROUNDED;
        case SYSTEM_CUTOFF:    return SHUTDOWN;
        }
        break;
    case IN_FLIGHT:
        switch (e) {
        case TAKEOFF_SIGNAL:   return IN_FLIGHT;
        case CRITICAL_BATTERY: return EMERGENCY_LANDING;
        case LANDED_SIGNAL:    return IN_FLIGHT;
        case SYSTEM_CUTOFF:    return IN_FLIGHT;
        }
        break;
    case EMERGENCY_LANDING:
        switch (e) {
        case TAKEOFF_SIGNAL:   return EMERGENCY_LANDING;
        case CRITICAL_BATTERY: return EMERGENCY_LANDING;
        case LANDED_SIGNAL:    return GROUNDED;
        case SYSTEM_CUTOFF:    return EMERGENCY_LANDING;
        }
        break;
    case SHUTDOWN:
        switch (e) {
        case TAKEOFF_SIGNAL:   return SHUTDOWN;
        case CRITICAL_BATTERY: return SHUTDOWN;
        case LANDED_SIGNAL:    return SHUTDOWN;
        case SYSTEM_CUTOFF:    return SHUTDOWN;
        }
        break;
    }
    return s; /* C exige um retorno após o switch */
}

static const char *STATE_NAME[] = {"Grounded", "InFlight", "EmergencyLanding", "Shutdown"};
static const char *EVENT_NAME[] = {"TakeoffSignal", "CriticalBattery", "LandedSignal", "SystemCutoff"};

int main(void)
{
    for (int s = GROUNDED; s <= SHUTDOWN; s++)
        for (int e = TAKEOFF_SIGNAL; e <= SYSTEM_CUTOFF; e++)
        {
            int r = (int)transition((state_t)s, (event_t)e);
            printf("%s %s %s\n", STATE_NAME[s], EVENT_NAME[e],
                   (r >= GROUNDED && r <= SHUTDOWN) ? STATE_NAME[r] : "INVALID");
        }
    return 0;
}
