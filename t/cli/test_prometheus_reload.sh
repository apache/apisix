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

git checkout conf/config.yaml

sleep 1

make run

sleep 2

echo "removing prometheus from the plugins list"
echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
  - ip-restriction' > conf/config.yaml

echo "fetch metrics, should not contain {}"

if curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should not contain '{}' when prometheus is enabled"
    exit 1
fi

echo "calling reload API to actually disable prometheus"

curl -i http://127.0.0.1:9090/v1/plugins/reload -XPUT

sleep 2

echo "fetch metrics after reload should contain {}"

if ! curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should contain '{}' when prometheus is disabled"
    exit 1
fi

echo "re-enable prometheus"

echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
  - prometheus' > conf/config.yaml

echo "fetching metrics without reloading should give same result as before"

if ! curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should contain '{}' when prometheus is disabled"
    exit 1
fi

echo "calling reload API to actually enable prometheus"

curl -i http://127.0.0.1:9090/v1/plugins/reload -XPUT

sleep 2

if curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should not contain '{}' when prometheus is enabled"
    exit 1
fi

echo "disable http prometheus and enable stream prometheus and call reload"

exit_if_not_customed_nginx

echo "
apisix:
    proxy_mode: http&stream
    enable_admin: true
    stream_proxy:
        tcp:
            - addr: 9100
plugins:
    - example-plugin
stream_plugins:
    - prometheus
" > conf/config.yaml

curl -i http://127.0.0.1:9090/v1/plugins/reload -XPUT

sleep 2

echo "fetching metrics should actually work demonstrating hot reload"

if ! curl -i http://127.0.0.1:9091/apisix/prometheus/metrics | grep "{}" > /dev/null; then
    echo "failed: metrics should not contain '{}' when prometheus is enabled"
    exit 1
fi
