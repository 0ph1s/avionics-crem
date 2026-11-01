/* Mesma FSM de aviônica em C++ (enum class), com enum e switch (estilo imperativo descrito por
 * Malakhovski e Shalyto). Serve de BASE DE COMPARAÇÃO com a versão em Haskell.
 * Imprime os 16 pares (estado, evento, destino) para ser conferido contra
 * spec/domain_rules.txt por compare-c/run.sh. */
#include <cstdio>

enum class state_t { GROUNDED, IN_FLIGHT, EMERGENCY_LANDING, SHUTDOWN };
enum class event_t { TAKEOFF_SIGNAL, CRITICAL_BATTERY, LANDED_SIGNAL, SYSTEM_CUTOFF };

state_t transition(state_t s, event_t e)
{
    switch (s) {
    case state_t::GROUNDED:
        switch (e) {
        case event_t::TAKEOFF_SIGNAL:   return state_t::IN_FLIGHT;
        case event_t::CRITICAL_BATTERY: return state_t::GROUNDED;
        case event_t::LANDED_SIGNAL:    return state_t::GROUNDED;
        case event_t::SYSTEM_CUTOFF:    return state_t::SHUTDOWN;
        }
        break;
    case state_t::IN_FLIGHT:
        switch (e) {
        case event_t::TAKEOFF_SIGNAL:   return state_t::IN_FLIGHT;
        case event_t::CRITICAL_BATTERY: return state_t::EMERGENCY_LANDING;
        case event_t::LANDED_SIGNAL:    return state_t::IN_FLIGHT;
        case event_t::SYSTEM_CUTOFF:    return state_t::IN_FLIGHT;
        }
        break;
    case state_t::EMERGENCY_LANDING:
        switch (e) {
        case event_t::TAKEOFF_SIGNAL:   return state_t::EMERGENCY_LANDING;
        case event_t::CRITICAL_BATTERY: return state_t::EMERGENCY_LANDING;
        case event_t::LANDED_SIGNAL:    return state_t::GROUNDED;
        case event_t::SYSTEM_CUTOFF:    return state_t::EMERGENCY_LANDING;
        }
        break;
    case state_t::SHUTDOWN:
        switch (e) {
        case event_t::TAKEOFF_SIGNAL:   return state_t::SHUTDOWN;
        case event_t::CRITICAL_BATTERY: return state_t::SHUTDOWN;
        case event_t::LANDED_SIGNAL:    return state_t::SHUTDOWN;
        case event_t::SYSTEM_CUTOFF:    return state_t::SHUTDOWN;
        }
        break;
    }
    return s; /* C exige um retorno após o switch */
}

static const char *STATE_NAME[] = {"Grounded", "InFlight", "EmergencyLanding", "Shutdown"};
static const char *EVENT_NAME[] = {"TakeoffSignal", "CriticalBattery", "LandedSignal", "SystemCutoff"};

int main()
{
    for (int s = 0; s <= 3; s++)
        for (int e = 0; e <= 3; e++)
        {
            int r = static_cast<int>(transition(static_cast<state_t>(s), static_cast<event_t>(e)));
            std::printf("%s %s %s\n", STATE_NAME[s], EVENT_NAME[e],
                        (r >= 0 && r <= 3) ? STATE_NAME[r] : "INVALID");
        }
    return 0;
}
