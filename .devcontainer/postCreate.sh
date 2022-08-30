#!/bin/bash
set -exo pipefail

make deps
make ci-env-up project_compose_ci=ci/pod/docker-compose.common.yml
make init
