#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

set -ex
clean_up() {
    if [ $? -gt 0 ]; then
      cat logs/error.log
      cat logs/error1.log
    fi
    ./bin/apisix stop
    kill $pid0
    git checkout conf/config.yaml
}

trap clean_up EXIT

wait_for_ready() {
  attempt=0
  while [ $attempt -le 10 ]; do
      if ! curl -s --fail http://127.0.0.1:$1/apisix/admin/routes \
            -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' > /dev/null 2>&1; then
          attempt=$((attempt + 1))
          sleep 1
      else
          break
      fi
  done
}


# start two gateway instances running on different port, this is a mock ha setup of gateway
#
# start first gateway and get the PID to kill after running test
# rm the PID file so that another instance can be started
cat ./ci/pod/apisix_conf/config0.yaml > conf/config.yaml
./bin/apisix start
wait_for_ready 9180

# start another gateway
pid0=$(cat logs/nginx.pid) && rm logs/nginx.pid
cat ./ci/pod/apisix_conf/config1.yaml > conf/config.yaml
./bin/apisix start
wait_for_ready 9181

# create a redis based rate limiting rule with delayed syncing
count=3
window=10
sync_interval=2

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9180/apisix/admin/routes \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X POST -d '{
  "uri": "/get",
  "plugins": {
    "limit-count": {
      "count": '$count',
      "time_window": '$window',
      "rejected_code": 504,
      "key": "remote_addr",
      "policy": "redis",
      "redis_host": "127.0.0.1",
      "redis_port": 6379,
      "sync_interval": '$sync_interval'
    }
  },
  "upstream": {
    "nodes": {
      "127.0.0.1:4901": 1
    },
    "type": "roundrobin"
  }
}' | grep -e 200 -e 201 || (echo "failed: creating route for test should succeed"; exit 1)
sleep 3 # wait for etcd sync to both gateways

last_time=$(date +%s)
# redis will be synced every $sync_interval seconds but
# it can take more $sync_interval seconds to propagate update to other gateways
sync_time=$((sync_interval+2))
# shdict reset can take (sync_interval + 1)s to propagate update to redis
shdict_counter_reset_time=$((window+sync_interval+1))

# send intial requests to fire off the timer in both gateways
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/get | grep 200 > /dev/null || (echo "failed: initial request to dp-A should pass"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 200 > /dev/null || ( curl -i http://127.0.0.1:9081/get || echo "failed: initial request to dp-B should pass"; exit 1)
echo "end intial"

# sending two requests to dp-A should pass, next requests will exceed the rate limiting rule so the requests will fail
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/get | grep 200 || (echo "failed: first request to dp-A should pass"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/get | grep 200 || (echo "failed: second request to dp-A should also pass"; exit 1)
sleep $sync_time
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 504 || (echo "failed: first request to dp-B should fail"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 504 || (echo "failed: second request to dp-B should also fail"; exit 1)

diff=$(($(date +%s)-last_time))
sleep $((shdict_counter_reset_time-diff)) # sleep to allow the counter to reset

last_time=$(date +%s)
# similar test as above but send request to dp-B first
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 200 || (echo "failed: first request to dp-B should pass"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 200 || (echo "failed: second request to dp-B should also pass"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 200 || (echo "failed: third request to dp-B should also pass"; exit 1)
sleep $sync_time
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/get | grep 504 || (echo "failed: first request to dp-A should fail"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/get | grep 504 || (echo "failed: second request to dp-A should also fail"; exit 1)

diff=$(($(date +%s)-last_time))
sleep $((shdict_counter_reset_time-diff)) # sleep to allow the counter to reset

# similar test but send 1-1 requests to both dps one by one
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 200 || (echo "failed: first request to dp-B should pass"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 200 || (echo "failed: second request to dp-B should pass"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/get | grep 200 || (echo "failed: first request to dp-A should also pass"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/get | grep 200 || (echo "failed: second request to dp-A should also pass"; exit 1)
sleep $sync_time
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9081/get | grep 504 || (echo "failed: third request to dp-B should fail"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/get | grep 504 || (echo "failed: third request to dp-A should also fail"; exit 1)
