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

# Enable limit-conn plugin

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
  - limit-conn
' > conf/config.yaml

make init
make run

admin_key="edd1c9f034335f136f87ad84b625c8f1"

# Create a route with limit-conn and redis policy
# key_ttl is set to 2 seconds
curl -X PUT http://127.0.0.1:9180/apisix/admin/routes/1 \
    -H "X-API-KEY: $admin_key" \
    -d '{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "key": "remote_addr",
            "policy": "redis",
            "redis_host": "127.0.0.1",
            "redis_timeout": 1000,
            "key_ttl": 2
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1995": 1
        },
        "timeout": {
            "connect": 300,
            "send": 300,
            "read": 300
        }
    }
}'

if [ $? -ne 0 ]; then
    echo "failed: verify route creation"
    exit 1
fi

sleep 0.5

# Start a mock upstream server (perl) that hangs.
# This ensures the connection stays open and limit-conn count remains 1.
perl -e 'use IO::Socket::INET; my $s = IO::Socket::INET->new(LocalPort => 1995, Listen => 1, Reuse => 1) or die; my $c = $s->accept(); sleep 10;' &
PERL_PID=$!
sleep 1

# Start the request in background.
# This request consumes the 1 allowed connection.
curl -v http://127.0.0.1:9080/hello > /dev/null 2>&1 &
CURL_PID=$!

sleep 1

# Kill APISIX hard (-9) to prevent limit-conn from decrementing the count.
# This simulates a crash where the Redis key is left with value 1.
if [ -f logs/nginx.pid ]; then
    pid=$(cat logs/nginx.pid)
    workers=$(pgrep -P $pid)
    kill -9 $pid || true
    echo "Killed APISIX master $pid"
    if [ -n "$workers" ]; then
        kill -9 $workers 2>/dev/null || true
    fi
fi

# Clean up the background tasks
kill $PERL_PID || echo "failed to kill upstream process"
kill $CURL_PID || echo "failed to kill curl process"

# Wait for key_ttl (2s) to expire in Redis.
# If key_ttl works, the key should expire and vanish.
echo "Waiting for key_ttl expiration..."
sleep 3

# Start APISIX again
rm logs/worker_events.sock || true
make run
sleep 1

# Start upstream again for the verification request
perl -e 'use IO::Socket::INET; my $s = IO::Socket::INET->new(LocalPort => 1995, Listen => 1, Reuse => 1) or die; my $c = $s->accept(); print $c "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n";' &
NC_2_PID=$!
sleep 1

# check connection
# If the key expired, this request should be allowed (we might get timeout or empty reply from nc, but NOT 503).
# If the key persisted (ttl features broken), connection count would still be 1, so this new request would result in 1+1 > 1 -> 503.
status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 http://127.0.0.1:9080/hello)

echo "Status code: $status_code"

# Cleanup
kill $NC_2_PID || true

if [ "$status_code" == "503" ]; then
    echo "failed: request blocked (503), limit-conn key did not expire"
    exit 1
fi

echo "pass: request not blocked, key_ttl works"
