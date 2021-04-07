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

make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/prometheus/metrics)
if [ ! $code -eq 404 ]; then
    echo "failed: should listen default prometheus address"
    exit 1
fi

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9091/apisix/prometheus/metrics)
if [ ! $code -eq 200 ]; then
    echo "failed: should listen default prometheus address"
    exit 1
fi

make stop

echo "passed: should listen default prometheus address"

echo '
plugin_attr:
  prometheus:
    export_addr:
        ip: ${{IP}}
        port: ${{PORT}}
' > conf/config.yaml

IP=127.0.0.1 PORT=9092 make run

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9092/apisix/prometheus/metrics)
if [ ! $code -eq 200 ]; then
    echo "failed: should listen configured prometheus address"
    exit 1
fi

make stop

echo "passed: should listen configured prometheus address"

echo '
plugin_attr:
  prometheus:
    enable_export_server: false
    export_uri: /prometheus/metrics
    export_addr:
        ip: ${{IP}}
        port: ${{PORT}}
' > conf/config.yaml

IP=127.0.0.1 PORT=9092 make run

code=$(curl -v -k -i -m 20 -o /dev/null -s http://127.0.0.1:9092/prometheus/metrics || echo 'ouch')
if [ "$code" != "ouch" ]; then
    echo "failed: should listen previous prometheus address"
    exit 1
fi

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/prometheus/metrics)
if [ ! $code -eq 200 ]; then
    echo "failed: should listen previous prometheus address"
    exit 1
fi

make stop

echo "passed: should listen previous prometheus address"
