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

# Enable limit-req plugin

rm logs/worker_events.sock || true

echo '
nginx_config:
  worker_processes: 1
  error_log_level: info
deployment:
  admin:
    admin_key:
      - name: "admin"
        key: edd1c9f034335f136f87ad84b625c8f1
        role: admin

apisix:
  enable_admin: true
  control:
    port: 9110
plugins:
  - limit-req
' > conf/config.yaml

make init
make run

admin_key="edd1c9f034335f136f87ad84b625c8f1"

# Create a route with limit-req and redis policy
# rate=1, burst=1 -> ttl = ceil(1/1) + 1 = 2s
curl -X PUT http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" \
    -d '{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "limit-req": {
            "rate": 1,
            "burst": 1,
            "key": "remote_addr",
            "policy": "redis",
            "redis_host": "127.0.0.1",
            "redis_timeout": 1000
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'

if [ $? -ne 0 ]; then
    echo "failed: verify route creation"
    exit 1
fi

sleep 0.5

# Make a request to create the Redis keys
curl -v http://127.0.0.1:9080/hello > /dev/null 2>&1

# Verify keys exist
# Keys pattern: plugin-limit-req*
keys=$(redis-cli keys "limit_req:*" | wc -l)
if [ "$keys" -eq 0 ]; then
    echo "failed: keys not found in Redis immediately after request"
    exit 1
fi
echo "pass: keys found in Redis"

# Wait for 3 seconds (TTL is 2s)
echo "Waiting for 3s..."
sleep 3

# Verify keys are gone
keys_list=$(redis-cli keys "limit_req:*")
keys_count=$(echo "$keys_list" | wc -l)

if [ "$keys_count" -ne 0 ] && [ -n "$keys_list" ]; then
    echo "failed: keys still exist in Redis after TTL expiration"
    echo "Keys found:"
    echo "$keys_list"
    
    first_key=$(echo "$keys_list" | head -n 1)
    echo "TTL of $first_key:"
    redis-cli ttl "$first_key"
    
    exit 1
fi

echo "pass: keys expired correctly"
make stop
