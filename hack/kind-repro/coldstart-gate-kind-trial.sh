#!/usr/bin/env bash
# End-to-end proof that a real Kubernetes Service + readinessProbe, pointed at
# the cold-start gate's /health_check_internal/ready, actually withholds
# traffic from a pod until its critical upstream has been probed -- the thing
# the plain-docker trial (coldstart-gate-trial.sh) cannot show, since a raw
# `docker run -p` has no readiness-probe concept at all.
#
# Requires: the kind cluster from kind-cluster.yaml already up (kind create
# cluster --config kind-cluster.yaml), mock-payments-api/mock-payproc already
# applied and Running, and apisix-repro:coldstart-gate already `kind load
# docker-image`d. Uses kubectl context kind-apisix-healthcheck-repro.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
CTX=kind-apisix-healthcheck-repro
NS=default

kubectl --context "$CTX" -n "$NS" delete deployment,service apisix-repro-coldstart --ignore-not-found >/dev/null 2>&1
kubectl --context "$CTX" -n "$NS" delete pod loadgen --ignore-not-found --grace-period=0 --force >/dev/null 2>&1
kubectl --context "$CTX" -n "$NS" apply -f manifests/apisix-config-coldstart-gate.yaml >/dev/null

./toggle.sh payments-api unhealthy >/dev/null

echo "=== starting loadgen pod (hammers the Service by DNS name before the apisix pod even exists) ==="
kubectl --context "$CTX" -n "$NS" run loadgen --image=curlimages/curl --restart=Never --command -- \
  sh -c 'i=0; while [ $i -lt 700 ]; do
    rm -f /tmp/body
    t=$(date +%s)
    code=$(curl -s -o /tmp/body -w "%{http_code}" --max-time 1 http://apisix-repro-coldstart.default.svc.cluster.local:9080/pay 2>/dev/null)
    body=$(cat /tmp/body 2>/dev/null | tail -c 100)
    echo "$t code=$code body=$body"
    i=$((i+1))
    sleep 0.05
  done' >/dev/null 2>&1

# wait for loadgen to actually be running before triggering the cold start
for i in $(seq 1 30); do
  phase=$(kubectl --context "$CTX" -n "$NS" get pod loadgen -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$phase" = "Running" ] && break
  sleep 0.3
done
echo "loadgen phase: $phase"

start=$(date +%s.%N)
echo "=== t=0: applying apisix-repro-coldstart deployment (the cold start) ==="
kubectl --context "$CTX" -n "$NS" apply -f manifests/apisix-deployment-coldstart-gate.yaml >/dev/null

# Poll readiness at high frequency, timestamped relative to $start.
ready_at=-1
for i in $(seq 1 150); do
  ready=$(kubectl --context "$CTX" -n "$NS" get pods -l app=apisix-repro-coldstart \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  now=$(date +%s.%N)
  elapsed=$(echo "$now - $start" | bc)
  if [ "$ready" = "true" ] && [ "$ready_at" = "-1" ]; then
    ready_at="$elapsed"
    echo "  t=+${elapsed}s: pod became Ready"
    break
  fi
  sleep 0.1
done
[ "$ready_at" = "-1" ] && echo "  pod never became Ready within the poll window"

sleep 15 # let the loadgen keep running well past the ready transition, for the "after" sample

echo "=== waiting for loadgen to finish ==="
kubectl --context "$CTX" -n "$NS" wait --for=condition=Ready=false pod/loadgen --timeout=5s >/dev/null 2>&1 || true
kubectl --context "$CTX" -n "$NS" logs loadgen > /tmp/loadgen-coldstart.log 2>&1

python3 - "$start" "$ready_at" <<'PYEOF'
import sys
start = float(sys.argv[1])
ready_at = float(sys.argv[2]) if sys.argv[2] != "-1" else None
lines = open("/tmp/loadgen-coldstart.log").read().splitlines()
before = {"total": 0, "leaked": 0, "correct": 0, "no_response": 0}
after = {"total": 0, "leaked": 0, "correct": 0, "no_response": 0}
for line in lines:
    parts = line.split(" ", 1)
    if not parts or not parts[0].replace(".", "", 1).isdigit():
        continue
    t = float(parts[0]) - start
    bucket = before if (ready_at is None or t < ready_at) else after
    bucket["total"] += 1
    # Only a genuine 201 response counts as leaked/correct -- code=000 (no
    # response) must never be classified by stale/absent body content.
    if "code=201" in line and "payments-api" in line:
        bucket["leaked"] += 1
    elif "code=201" in line and "payproc" in line:
        bucket["correct"] += 1
    elif "code=000" in line:
        bucket["no_response"] += 1
print(f"ready_at = {ready_at}")
print(f"BEFORE ready: total={before['total']} leaked_to_payments_api={before['leaked']} correct_payproc={before['correct']} no_response={before['no_response']}")
print(f"AFTER  ready: total={after['total']} leaked_to_payments_api={after['leaked']} correct_payproc={after['correct']} no_response={after['no_response']}")
PYEOF

echo "=== apisix pod logs (health-check gate lines) ==="
POD=$(kubectl --context "$CTX" -n "$NS" get pods -l app=apisix-repro-coldstart -o jsonpath='{.items[0].metadata.name}')
kubectl --context "$CTX" -n "$NS" logs "$POD" 2>&1 | grep -E "critical upstream|health-check" | tail -20

kubectl --context "$CTX" -n "$NS" delete pod loadgen --ignore-not-found --grace-period=0 --force >/dev/null 2>&1
./toggle.sh payments-api healthy >/dev/null
echo "=== done (full loadgen log: /tmp/loadgen-coldstart.log) ==="
