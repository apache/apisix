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

# file-logger: write to stdout via /dev/stdout

echo '
apisix:
  node_listen: 9080
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
nginx_config:
  main_configuration_snippet: |
    daemon off;
' > conf/config.yaml

echo '
routes:
  - uri: /hello
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
    plugins:
      file-logger:
        path: /dev/stdout
#END
' > conf/apisix.yaml

make init

./bin/apisix start > stdout.log 2>&1 &
apisix_pid=$!
sleep 1

curl -s http://127.0.0.1:9080/hello > /dev/null
sleep 2

kill "$apisix_pid" 2>/dev/null || true
wait "$apisix_pid" 2>/dev/null || true

if ! grep -q "uri.*hello" stdout.log; then
    echo "failed: file-logger did not write to stdout"
    cat stdout.log
    exit 1
fi

echo "passed: file-logger stdout support"
