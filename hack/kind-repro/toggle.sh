#!/usr/bin/env bash
# Usage: ./toggle.sh <payments-api|payproc> <healthy|unhealthy>
#
# Flips a sentinel file under state/<backend>/unhealthy. This directory is
# bind-mounted into the kind node via kind-cluster.yaml's extraMounts, and
# from there into the mock backend pod via a hostPath volume -- same
# mechanism as the docker-compose POC at
# ~/Mollie/edge-app/docs/poc/0003-apisix-healthcheck-worker-repro/toggle.sh,
# just relayed through one extra hop (host -> kind node -> pod) since kind
# pods can't bind-mount the host directly.
set -euo pipefail

backend="${1:?backend required: payments-api or payproc}"
state="${2:?state required: healthy or unhealthy}"

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state/$backend"
mkdir -p "$dir"

if [ "$state" = "unhealthy" ]; then
  touch "$dir/unhealthy"
else
  rm -f "$dir/unhealthy"
fi

echo "$backend -> $state"
