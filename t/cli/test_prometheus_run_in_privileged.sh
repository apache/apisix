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

exit_if_not_customed_nginx

# prometheus run in privileged works when only http is enabled
sleep 0.5
rm logs/error.log || true

echo '
apisix:
    extra_lua_path: "$prefix/t/lib/?.lua"
nginx_config:
    error_log_level: info
' > conf/config.yaml

make run
sleep 0.1

curl -s -o /dev/null http://127.0.0.1:9091/apisix/prometheus/metrics

if ! grep -E "process type: privileged agent" logs/error.log; then
    echo "failed: prometheus run in privileged can't work when only http is enabled"
    exit 1
fi

make stop

echo "prometheus run in privileged agent successfully when only http is enabled"


# prometheus run in privileged works when both http & stream are enabled
sleep 0.5
rm logs/error.log || true

echo '
apisix:
    proxy_mode: http&stream
    extra_lua_path: "$prefix/t/lib/?.lua"
    enable_admin: true
    stream_proxy:
        tcp:
            - addr: 9100
stream_plugins:
    - prometheus
nginx_config:
    error_log_level: info
' > conf/config.yaml

make run
sleep 0.1

curl -s -o /dev/null http://127.0.0.1:9091/apisix/prometheus/metrics

if ! grep -E " process type: privileged agent" logs/error.log; then
    echo "failed: prometheus run in privileged can't work when both http & stream are enabled"
    exit 1
fi

echo "passed: prometheus run in privileged agent successfully when both http & stream are enabled"

make stop


# prometheus run in privileged works when only stream is enabled
sleep 0.5
rm logs/error.log || true

echo '
apisix:
    proxy_mode: http&stream
    extra_lua_path: "$prefix/t/lib/?.lua"
    enable_admin: false
    stream_proxy:
        tcp:
            - addr: 9100
stream_plugins:
    - prometheus
nginx_config:
    error_log_level: info
' > conf/config.yaml

make run
sleep 0.1

curl -s -o /dev/null http://127.0.0.1:9091/apisix/prometheus/metrics

if ! grep -E " process type: privileged agent" logs/error.log; then
    echo "failed: prometheus run in privileged can't work when only stream is enabled"
    exit 1
fi

echo "passed: prometheus run in privileged agent successfully when only stream is enabled"
