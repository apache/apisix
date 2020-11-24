#! /bin/bash -x

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

if [ -n "$1" ]; then
    worker_cnt=$1
else
    worker_cnt=1
fi

mkdir -p benchmark/server/logs
mkdir -p benchmark/fake-apisix/logs

sudo openresty -p $PWD/benchmark/server || exit 1

make init

trap 'onCtrlC' INT
function onCtrlC () {
    sudo killall wrk
    sudo killall openresty
    sudo openresty -p $PWD/benchmark/fake-apisix -s stop || exit 1
    sudo openresty -p $PWD/benchmark/server -s stop || exit 1
}

if [[ "$(uname)" == "Darwin" ]]; then
    sed  -i "" "s/worker_processes .*/worker_processes $worker_cnt;/g" conf/nginx.conf
else
    sed  -i "s/worker_processes .*/worker_processes $worker_cnt;/g" conf/nginx.conf
fi

make run

sleep 3

#############################################
echo -e "\n\napisix: $worker_cnt worker + 1 upstream + no plugin"

curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

#############################################
echo -e "\n\napisix: $worker_cnt worker + 1 upstream + 2 plugins (limit-count + prometheus)"

curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "limit-count": {
            "count": 2000000000000,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        },
        "prometheus": {}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'

sleep 3

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

make stop

#############################################
echo -e "\n\nfake empty apisix server: $worker_cnt worker"

sleep 1

sed  -i "s/worker_processes [0-9]*/worker_processes $worker_cnt/g" benchmark/fake-apisix/conf/nginx.conf
sudo openresty -p $PWD/benchmark/fake-apisix || exit 1

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sudo openresty -p $PWD/benchmark/fake-apisix -s stop || exit 1

sudo openresty -p $PWD/benchmark/server -s stop || exit 1
