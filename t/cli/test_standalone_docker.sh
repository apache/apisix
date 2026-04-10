#!/usr/bin/env bash

#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

. ./t/cli/common.sh

standalone() {
    clean_up
    docker rm -f apisix-test-standalone 2>/dev/null || true
    git checkout conf/apisix.yaml
}

DOCKER_IMAGE="${DOCKER_IMAGE:-apache/apisix:master-debian-dev}"
trap standalone EXIT

echo 'routes: []
#END' > conf/apisix.yaml

run_docker_test() {
    local standalone_flag=$1
    local config_mode=${2:-ro}

    if [ "$standalone_flag" = "true" ]; then
        docker run -d --name apisix-test-standalone \
            -e APISIX_STAND_ALONE=true \
            -v $(pwd)/conf/config.yaml:/usr/local/apisix/conf/config.yaml:${config_mode} \
            -v $(pwd)/conf/apisix.yaml:/usr/local/apisix/conf/apisix.yaml:ro \
            ${DOCKER_IMAGE} > /dev/null 2>&1
    else
        docker run -d --name apisix-test-standalone \
            -v $(pwd)/conf/config.yaml:/usr/local/apisix/conf/config.yaml:${config_mode} \
            -v $(pwd)/conf/apisix.yaml:/usr/local/apisix/conf/apisix.yaml:ro \
            ${DOCKER_IMAGE} > /dev/null 2>&1
    fi

    sleep 5

    if ! docker ps | grep -q apisix-test-standalone; then
        echo "Container failed to start. Logs:"
        docker logs apisix-test-standalone
        docker rm -f apisix-test-standalone > /dev/null 2>&1
        return 1
    fi

    docker rm -f apisix-test-standalone > /dev/null 2>&1
    return 0
}

# normal YAML format
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
apisix:
    node_listen: 9080
' > conf/config.yaml

if ! run_docker_test "true"; then
    echo "failed: normal YAML format 'role: data_plane' was rejected"
    exit 1
fi

echo "passed: normal YAML format accepted"

# double-quoted format
echo '
deployment:
    role: "data_plane"
    role_data_plane:
        config_provider: yaml
apisix:
    node_listen: 9080
' > conf/config.yaml

if ! run_docker_test "true"; then
    echo "failed: double-quoted 'role: \"data_plane\"' was rejected"
    exit 1
fi

echo "passed: double-quoted format accepted"

# single-quoted format
echo "
deployment:
    role: 'data_plane'
    role_data_plane:
        config_provider: yaml
apisix:
    node_listen: 9080
" > conf/config.yaml

if ! run_docker_test "true"; then
    echo "failed: single quoted \"role: 'data_plane'\" was rejected"
    exit 1
fi

echo "passed: single-quoted format accepted"

# flow syntax
echo '
deployment: {"role": "data_plane", "role_data_plane": {"config_provider": "yaml"}}
apisix:
    node_listen: 9080
' > conf/config.yaml

if ! run_docker_test "true"; then
    echo "failed: flow syntax 'role: {\"data_plane\"}' was rejected"
    exit 1
fi

echo "passed: flow syntax format accepted"

# mixed quotes
echo "
deployment:
    role: \"data_plane\"
    role_data_plane:
        config_provider: 'yaml'
apisix:
    node_listen: 9080
" > conf/config.yaml

if ! run_docker_test "true"; then
    echo "failed: mixed quotes format was rejected"
    exit 1
fi

echo "passed: mixed quotes format accepted"

# etcd config_provider should fail in standalone mode
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: etcd
    etcd:
        host:
            - "http://127.0.0.1:2379"
apisix:
    node_listen: 9080
' > conf/config.yaml

if run_docker_test "true"; then
    echo "failed: 'config_provider: etcd' should be rejected in standalone mode"
    exit 1
fi

echo "passed: 'config_provider: etcd' was correctly rejected in standalone mode"

# traditional role with yaml config_provider should work
echo '
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
    admin:
        admin_key_required: false
apisix:
    node_listen: 9080
    enable_admin: true
' > conf/config.yaml

if ! run_docker_test "true" "rw"; then
    echo "failed: traditional role with 'config_provider: yaml' was rejected"
    exit 1
fi

echo "passed: traditional role with 'config_provider: yaml' accepted"

# check is APISIX_PROFILE is respected in standalone mode
echo '
  deployment:
    role: data_plane
    role_data_plane:
      config_provider: yaml
  apisix:
    node_listen: 9080
  ' > conf/config-prod.yaml

  docker run -d --name apisix-test-standalone \
      -e APISIX_STAND_ALONE=true \
      -e APISIX_PROFILE=prod \
      -v $(pwd)/conf/config-prod.yaml:/usr/local/apisix/conf/config-prod.yaml:ro \
      -v $(pwd)/conf/apisix.yaml:/usr/local/apisix/conf/apisix.yaml:ro \
      ${DOCKER_IMAGE} > /dev/null 2>&1

  sleep 5

  if ! docker ps | grep -q apisix-test-standalone; then
      echo "failed: APISIX_PROFILE=prod in standalone mode was rejected"
      docker logs apisix-test-standalone
      docker rm -f apisix-test-standalone > /dev/null 2>&1
      exit 1
  fi

  docker rm -f apisix-test-standalone > /dev/null 2>&1

  echo "passed: APISIX_PROFILE=prod in standalone mode accepted"
