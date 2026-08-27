#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
PASSIVE_SUCCESSES="${1:?2 or 0}"
IMAGE="${2:-apisix-repro:3.15.0}"

sed "s/PASSIVE_SUCCESSES_PLACEHOLDER/${PASSIVE_SUCCESSES}/" coldstart-apisix.yaml > coldstart-apisix-rendered.yaml

docker rm -f coldstart-apisix >/dev/null 2>&1 || true
./toggle.sh payments-api unhealthy >/dev/null
docker run -d --name coldstart-apisix --network apisix-race-net -p 19084:9080 \
  -e APISIX_STAND_ALONE=true \
  -v "$(pwd)/nilwindow-config.yaml:/usr/local/apisix/conf/config.yaml:ro" \
  -v "$(pwd)/coldstart-apisix-rendered.yaml:/usr/local/apisix/conf/apisix.yaml:ro" \
  "$IMAGE" >/dev/null
start=$SECONDS
echo "=== passive.successes=$PASSIVE_SUCCESSES, image=$IMAGE ==="
leaked=0; total=0; first_correct=-1
for i in $(seq 1 60); do
  b=$(curl -s --max-time 1 -o /dev/null -w '%header{X-Mock-Backend}' http://127.0.0.1:19084/pay 2>/dev/null)
  elapsed=$((SECONDS - start))
  total=$((total+1))
  if [ "$b" = "payments-api" ]; then
    leaked=$((leaked+1))
    echo "  t=+${elapsed}s req $i: $b  <-- leaked"
  else
    [ "$first_correct" = "-1" ] && [ -n "$b" ] && first_correct=$elapsed
  fi
  sleep 0.2
done
echo "=== passive.successes=$PASSIVE_SUCCESSES: $leaked/$total leaked, first correct at t=+${first_correct}s ==="
docker rm -f coldstart-apisix >/dev/null 2>&1
./toggle.sh payments-api healthy >/dev/null
