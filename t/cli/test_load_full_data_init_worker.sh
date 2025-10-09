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

echo '
apisix:
  worker_startup_time_threshold: 3
' > conf/config.yaml

make run

sleep 5

MASTER_PID=$(cat logs/nginx.pid)

worker_pids=$(pgrep -P "$MASTER_PID" -f "nginx: worker process" || true)

if [ -n "$worker_pids" ]; then
    pid=$(echo "$worker_pids" | shuf -n 1)
    echo "killing worker $pid (master $MASTER_PID)"
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

echo "passed: load full configuration for new worker"

make stop
