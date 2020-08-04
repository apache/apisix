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

trap 'onCtrlC' INT
function onCtrlC () {
    killall wrk
    killall openresty
    openresty -p $PWD/benchmark/server -s stop
    sudo docker stop envoy
}

function run_wrk() {
    connections=`expr $worker_cnt \* 16`
    wrk -d 5 -t $worker_cnt -c ${connections} http://127.0.0.1:10000/hello
}

openresty -p $PWD/benchmark/server || exit 1

sudo docker run --name=envoy --rm -d \
    --network=host \
    -v $(pwd)/config.yaml:/etc/envoy/envoy.yaml \
    envoyproxy/envoy:v1.14-latest  -c /etc/envoy/envoy.yaml --concurrency ${worker_cnt}

sleep 1

curl http://127.0.0.1:10000/hello

sleep 1

run_wrk

sleep 1

run_wrk

sleep 1

onCtrlC
