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

if [ -n "$2" ]; then
    upstream_cnt=$2
else
    upstream_cnt=1
fi

mkdir -p benchmark/server/logs
mkdir -p benchmark/fake-apisix/logs


make init

trap 'onCtrlC' INT
function onCtrlC () {
    sudo killall wrk
    sudo killall openresty
    sudo openresty -p $PWD/benchmark/fake-apisix -s stop || exit 1
    sudo openresty -p $PWD/benchmark/server -s stop || exit 1
}

for up_cnt in $(seq 1 $upstream_cnt);
do
    port=$((1979+$up_cnt))
    nginx_listen=$nginx_listen"listen $port;"
    upstream_nodes=$upstream_nodes"\"127.0.0.1:$port\":1"

    if [ $up_cnt -lt $upstream_cnt ]; then
        upstream_nodes=$upstream_nodes","
    fi
done

if [[ "$(uname)" == "Darwin" ]]; then
    sed  -i "" "s/worker_processes .*/worker_processes $worker_cnt;/g" conf/nginx.conf
    sed  -i "" "s/listen .*;/$nginx_listen/g" benchmark/server/conf/nginx.conf
else
    sed  -i "s/worker_processes .*/worker_processes $worker_cnt;/g" conf/nginx.conf
    sed  -i "s/listen .*;/$nginx_listen/g" benchmark/server/conf/nginx.conf
fi

sudo openresty -p $PWD/benchmark/server || exit 1

make run

sleep 3

#############################################
echo -e "\n\napisix: $worker_cnt worker + $upstream_cnt upstream + no plugin"

curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            '$upstream_nodes'
        }
    }
}'

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

#############################################
echo -e "\n\napisix: $worker_cnt worker + $upstream_cnt upstream + 2 plugins (limit-count + prometheus)"

curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
            '$upstream_nodes'
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

if [[ "$(uname)" == "Darwin" ]]; then
    sed  -i "" "s/worker_processes [0-9]*/worker_processes $worker_cnt/g" benchmark/fake-apisix/conf/nginx.conf
else
    sed  -i "s/worker_processes [0-9]*/worker_processes $worker_cnt/g" benchmark/fake-apisix/conf/nginx.conf
fi

sudo openresty -p $PWD/benchmark/fake-apisix || exit 1

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sleep 1

wrk -d 5 -c 16 http://127.0.0.1:9080/hello

sudo openresty -p $PWD/benchmark/fake-apisix -s stop || exit 1

sudo openresty -p $PWD/benchmark/server -s stop || exit 1
