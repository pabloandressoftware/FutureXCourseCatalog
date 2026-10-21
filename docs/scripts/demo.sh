#!/usr/bin/env bash
# Demostración del Circuit Breaker, Retry y RateLimiter de Resilience4j en fx-catalog-service.
# Requiere Eureka + fx-catalog-service en marcha (scripts/run-all.sh). Controla fx-course-service por sí mismo.
cd "$(dirname "$0")/.."
CAT=http://localhost:8002
OUT=evidencia/demo_resilience4j.txt
: > "$OUT"
say()  { echo -e "$*" | tee -a "$OUT"; }
hit()  { local code body; body=$(curl -s -o /tmp/r4j_body -w "%{http_code}" "$CAT$1"); code=$body; say "  GET $1 -> [HTTP $code] $(cut -c1-140 /tmp/r4j_body)"; }
state(){ say "  Circuit Breaker 'courseService': $(curl -s $CAT/actuator/circuitbreakers | python3 -c "import sys,json; c=json.load(sys.stdin)['circuitBreakers']['courseService']; print(c['state'], '| failureRate', c['failureRate'], '| failedCalls', c['failedCalls'], '| notPermitted', c['notPermittedCalls'])")"; }
start_course() { nohup java -jar fx-course-service/target/FutureXCourseApp-0.0.1-SNAPSHOT.jar > logs/course.log 2>&1 & echo $! > logs/course.pid
  until curl -s -o /dev/null localhost:8001/; do sleep 2; done; sleep 3; }
stop_course()  { [ -f logs/course.pid ] && kill "$(cat logs/course.pid)" 2>/dev/null; pkill -f "fx-course-service/target" 2>/dev/null; sleep 6; }

say "=== ESCENARIO 1: todo funcionando (course-service UP, circuito CLOSED) ==="
hit /; hit /catalog; hit /firstcourse; state

say "\n=== ESCENARIO 2: se detiene fx-course-service -> fallback y apertura del circuito ==="
stop_course
for i in 1 2 3 4 5 6; do say "  [llamada $i]"; hit /catalog; done
state

say "\n=== ESCENARIO 3: circuito OPEN rechaza sin intentar la llamada (fail fast) ==="
hit /; hit /firstcourse; state

say "\n=== ESCENARIO 4: se reinicia fx-course-service; tras 5 s el circuito pasa a HALF_OPEN y luego a CLOSED ==="
start_course
say "  (esperando 45 s: Eureka server y la caché local del catálogo deben ver de nuevo a fx-course-service;"
say "   mientras tanto el circuito ya pasó solo de OPEN a HALF_OPEN tras 5 s)"
sleep 45
hit /; hit /catalog; hit /firstcourse; state

say "\n=== ESCENARIO 5: RateLimiter (5 llamadas / 10 s) sobre /firstcourse ==="
sleep 10
for i in 1 2 3 4 5 6 7; do hit /firstcourse; done
say "\n=== Eventos del Circuit Breaker (actuator/circuitbreakerevents) ==="
curl -s $CAT/actuator/circuitbreakerevents/courseService | python3 -c "
import sys,json
for e in json.load(sys.stdin)['circuitBreakerEvents'][-12:]:
    print('  ', e['creationTime'][11:23], e['type'], e.get('stateTransition',''), (e.get('errorMessage') or '')[:70])" | tee -a "$OUT"
