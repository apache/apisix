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

serverless_clean_up() {
    clean_up
    git checkout conf/apisix.yaml
}

trap serverless_clean_up EXIT

rm logs/error.log || echo ''

echo '
apisix:
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
' > conf/config.yaml

make init

echo '
routes:
  -
    uri: /log_request
    plugins:
      serverless-pre-function:
        phase: before_proxy
        functions:
        - "return function(conf, ctx) ctx.count = (ctx.count or 0) + 1 end"
        - "return function(conf, ctx) ngx.log(ngx.WARN, \"run before_proxy phase \", ctx.count, \" with \", ctx.balancer_ip) end"
    upstream:
      nodes:
        "127.0.0.1:1980": 1
        "0.0.0.0:1979": 100000
      type: chash
      key: remote_addr
#END
' > conf/apisix.yaml

make run
sleep 0.1
curl -v -k -i -m 20 -o /dev/null http://127.0.0.1:9080/log_request

if ! grep "run before_proxy phase 1 with 0.0.0.0" logs/error.log; then
    echo "failed: before_proxy phase runs incorrect time"
    exit 1
fi

if ! grep "run before_proxy phase 2 with 127.0.0.1" logs/error.log; then
    echo "failed: before_proxy phase runs incorrect time"
    exit 1
fi

make stop

echo '
routes:
  -
    uri: /log_request
    plugins:
      serverless-pre-function:
        phase: before_proxy
        functions:
        - "return function(conf, ctx) ngx.exit(403) end"
    upstream:
      nodes:
        "127.0.0.1:1980": 1
        "0.0.0.0:1979": 100000
      type: chash
      key: remote_addr
#END
' > conf/apisix.yaml

make run
sleep 0.1
code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/log_request)
make stop

if [ ! $code -eq 403 ]; then
    echo "failed: failed to exit in the before_proxy phase"
    exit 1
fi

make stop

echo "pass: run code in the before_proxy phase of serverless plugin"
