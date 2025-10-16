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

# . ./t/cli/common.sh

git checkout conf/config.yaml

echo '
apisix:
  worker_startup_time_threshold: 3
nginx_config:
  worker_processes: 1
  http_configuration_snippet: |
    server {
        listen 1980;
        location /hello {
            return 200 "hello world";
        }
    }
' > conf/config.yaml

make run

sleep 5

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl -k -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/hello",
    "upstream": {
        "nodes": {
            "127.0.0.1:1980": 1
        },
        "scheme": "http",
        "type": "roundrobin"
    }
}'

sleep 1

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/hello)
if [ ! $code -eq 200 ]; then
    echo "failed: request failed, http status $code"
    exit 1
fi

MASTER_PID=$(cat logs/nginx.pid)

worker_pid=$(pgrep -P "$MASTER_PID" -f "nginx: worker process" || true)

if [ -n "$worker_pid" ]; then
    echo "killing worker $worker_pid (master $MASTER_PID)"
    kill "$pid"
else
    echo "failed: no worker process found for master $MASTER_PID"
    exit 1
fi

sleep 2

if ! grep 'master process has been running for a long time, reloading the full configuration from etcd for this new worker' logs/error.log; then
    echo "failed: could not detect new worker be started"
    exit 1
fi

if grep 'API disabled in the context of init_worker_by_lua' logs/error.log; then
    echo "failed: cannot access etcd in init_worker phase"
    exit 1
fi

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/hello)
if [ ! $code -eq 200 ]; then
    echo "failed: request failed for new worker, http status $code"
    exit 1
fi

echo "passed: load full configuration for new worker"

make stop
