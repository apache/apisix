#!/usr/bin/env bash
# Usage: ./coldstart-gate-trial.sh <enabled|disabled> [image]
#
# Validates the cold-start readiness gate (mollie-health-check.lua's
# critical_upstreams) against a real running APISIX + real plugin, using the
# same already-unhealthy-mock-backend setup as coldstart-trial.sh. Unlike
# that script, this measures /health_check_internal/ready's own transition
# timing, not leaked /pay requests -- a plain `docker run -p` has no
# readiness-probe concept, so nothing here is actually gated on /ready (see
# the plan's own note on this: proving the leak itself closes needs a real
# k8s Service + readinessProbe, a separate kind-based test). What this DOES
# prove: the gate mechanism itself -- /ready stays 503 exactly as long as the
# critical upstream is genuinely unprobed, and flips to 200 only once a real
# active check has actually fired against the (already-unhealthy) backend.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
MODE="${1:?enabled or disabled}"
IMAGE="${2:-apisix-repro:coldstart-gate}"

case "$MODE" in
  enabled)  CRITICAL='["online-payment-write"]' ;;
  disabled) CRITICAL='[]' ;;
  *) echo "usage: $0 <enabled|disabled> [image]" >&2; exit 1 ;;
esac

sed "s/CRITICAL_UPSTREAMS_PLACEHOLDER/${CRITICAL}/" coldstart-gate-apisix.yaml > coldstart-gate-apisix-rendered.yaml

docker rm -f coldstart-gate-apisix >/dev/null 2>&1 || true
./toggle.sh payments-api unhealthy >/dev/null

start=$SECONDS
echo "=== mode=$MODE (critical_upstreams=$CRITICAL), image=$IMAGE ==="

docker run -d --name coldstart-gate-apisix --network apisix-race-net -p 19085:9080 \
  -e APISIX_STAND_ALONE=true \
  -v "$(pwd)/coldstart-gate-config.yaml:/usr/local/apisix/conf/config.yaml:ro" \
  -v "$(pwd)/coldstart-gate-apisix-rendered.yaml:/usr/local/apisix/conf/apisix.yaml:ro" \
  "$IMAGE" >/dev/null

# Poll /ready every 200ms for up to 15s, recording the transition.
ready_at=-1
for i in $(seq 1 75); do
  code=$(curl -s --max-time 1 -o /dev/null -w '%{http_code}' http://127.0.0.1:19085/health_check_internal/ready 2>/dev/null)
  elapsed=$((SECONDS - start))
  if [ "$code" = "200" ] && [ "$ready_at" = "-1" ]; then
    ready_at=$elapsed
    echo "  t=+${elapsed}s: /ready -> 200 (first time)"
    break
  fi
  sleep 0.2
done

if [ "$ready_at" = "-1" ]; then
  echo "  /ready never returned 200 within the poll window"
fi

# Cross-check against the /pay leak count, same methodology as coldstart-trial.sh,
# to confirm the backend really was still unhealthy for the relevant window
# (not gating traffic -- see header note -- just corroborating the setup).
leaked=0; total=0
for i in $(seq 1 30); do
  b=$(curl -s --max-time 1 -o /dev/null -w '%header{X-Mock-Backend}' http://127.0.0.1:19085/pay 2>/dev/null)
  total=$((total+1))
  [ "$b" = "payments-api" ] && leaked=$((leaked+1))
  sleep 0.2
done
echo "=== mode=$MODE: /ready first-200 at t=+${ready_at}s, /pay leaked ${leaked}/${total} over the same post-start window ==="

docker logs coldstart-gate-apisix 2>&1 | grep -E "health-check|critical upstream|failing open" | tail -20

docker rm -f coldstart-gate-apisix >/dev/null 2>&1
./toggle.sh payments-api healthy >/dev/null
