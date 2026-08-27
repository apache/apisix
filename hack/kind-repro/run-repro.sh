#!/usr/bin/env bash
# Local kind e2e repro: does the apache/apisix#13888 patch change leak
# count/duration during a real k8s rolling pod replacement?
#
# See /Users/andre.nogueira/.claude/plans/enchanted-chasing-sky.md for the
# full design. Usage:
#
#   ./run-repro.sh setup              # create cluster, build+load all images
#   ./run-repro.sh variant stock      # run one variant against a live cluster
#   ./run-repro.sh variant patched
#   ./run-repro.sh teardown           # delete kind cluster
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd ../.. && pwd)"
CLUSTER=apisix-healthcheck-repro
RESULTS_DIR=./results
mkdir -p "$RESULTS_DIR"

log() { echo "[run-repro] $*" >&2; }

cmd_setup() {
  log "building mock images"
  docker build -t apisix-repro/mock-payments-api:local --build-arg BACKEND_CONF=payments-api.conf ./mock
  docker build -t apisix-repro/mock-payproc:local --build-arg BACKEND_CONF=payproc.conf ./mock

  log "building apisix images (stock + patched) from $REPO_ROOT -- this compiles openresty from source, several minutes each"
  docker build -f ./Dockerfile -t apisix-repro:stock "$REPO_ROOT"
  docker build -f ./Dockerfile --build-arg APPLY_PATCH=true -t apisix-repro:patched "$REPO_ROOT"

  log "creating kind cluster"
  kind create cluster --config ./kind-cluster.yaml --name "$CLUSTER"

  log "loading images into kind"
  for img in apisix-repro/mock-payments-api:local apisix-repro/mock-payproc:local apisix-repro:stock apisix-repro:patched; do
    kind load docker-image "$img" --name "$CLUSTER"
  done

  log "applying mocks + config"
  kubectl apply -f manifests/mock-payments-api.yaml -f manifests/mock-payproc.yaml -f manifests/apisix-config.yaml
  kubectl wait --for=condition=available --timeout=60s deployment/mock-payments-api deployment/mock-payproc

  log "setup done"
}

cmd_teardown() {
  kind delete cluster --name "$CLUSTER" || true
  docker rmi apisix-repro:stock apisix-repro:patched apisix-repro/mock-payments-api:local apisix-repro/mock-payproc:local 2>/dev/null || true
}

# Render apisix-deployment.yaml with the given image + probe timing, apply it,
# wait for it to be ready.
apply_apisix_deployment() {
  local image="$1" min_ready="$2" readiness_delay="$3"
  sed -e "s|__APISIX_IMAGE__|$image|" \
      -e "s|__MIN_READY_SECONDS__|$min_ready|" \
      -e "s|__READINESS_INITIAL_DELAY__|$readiness_delay|" \
      manifests/apisix-deployment.yaml | kubectl apply -f -
  kubectl rollout status deployment/apisix-repro --timeout=120s
}

# Hammer the NodePort service, one line per response to $1, tagging pod +
# backend + timestamp. Runs for $2 seconds.
hammer() {
  local outfile="$1" duration="$2"
  local end=$((SECONDS + duration))
  : > "$outfile"
  while [ $SECONDS -lt $end ]; do
    resp=$(curl -s --max-time 2 -o /dev/null -w '%{http_code} %header{X-Mock-Backend}\n' \
      -H 'Host: localhost' "http://127.0.0.1:30980/pay" 2>/dev/null || echo "ERR")
    echo "$(date +%s.%N) $resp" >> "$outfile"
  done
}

cmd_variant() {
  local variant="$1"   # stock | patched
  local probe_mode="${2:-fast}"  # fast (no mitigation) | mitigated (prod IMP-3220 values)
  local image="apisix-repro:$variant"
  local min_ready=0 readiness_delay=0
  if [ "$probe_mode" = "mitigated" ]; then
    min_ready=30
    readiness_delay=30
  fi

  log "=== variant=$variant probe_mode=$probe_mode ==="
  ./toggle.sh payments-api healthy

  log "deploying $image (minReadySeconds=$min_ready readinessInitialDelay=$readiness_delay)"
  apply_apisix_deployment "$image" "$min_ready" "$readiness_delay"

  log "baseline check"
  sleep 2
  curl -s -o /dev/null -w 'baseline: %{http_code} backend=%header{X-Mock-Backend}\n' \
    "http://127.0.0.1:30980/pay"

  log "toggling payments-api unhealthy, waiting for steady-state convergence to payproc (measured ~45s locally, single pod)"
  ./toggle.sh payments-api unhealthy
  for i in $(seq 1 120); do
    sleep 1
    backend=$(curl -s -o /dev/null -w '%header{X-Mock-Backend}' "http://127.0.0.1:30980/pay")
    [ $((i % 5)) -eq 0 ] && log "  convergence check $i: backend=$backend"
    [ "$backend" = "payproc" ] && { log "  converged after ${i}s"; break; }
  done

  local outfile="$RESULTS_DIR/${variant}-${probe_mode}.log"
  log "triggering rollout restart, hammering for 90s -> $outfile"
  kubectl rollout restart deployment/apisix-repro
  hammer "$outfile" 90 &
  local hammer_pid=$!
  kubectl rollout status deployment/apisix-repro --timeout=120s || true
  wait "$hammer_pid"

  local total leaked
  total=$(wc -l < "$outfile")
  leaked=$(grep -c 'payments-api' "$outfile" || true)
  log "variant=$variant probe_mode=$probe_mode: total=$total leaked_to_payments_api=$leaked"

  ./toggle.sh payments-api healthy
  kubectl delete deployment apisix-repro --ignore-not-found
}

case "${1:-}" in
  setup) cmd_setup ;;
  teardown) cmd_teardown ;;
  variant) shift; cmd_variant "$@" ;;
  *) echo "usage: $0 {setup|variant <stock|patched> [fast|mitigated]|teardown}" >&2; exit 1 ;;
esac
