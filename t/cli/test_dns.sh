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

# 'make init' operates scripts and related configuration files in the current directory
# The 'apisix' command is a command in the /usr/local/apisix,
# and the configuration file for the operation is in the /usr/local/apisix/conf

. ./t/cli/common.sh

# dns_resolver_valid
echo '
apisix:
  dns_resolver:
    - 127.0.0.1
    - "[::1]:5353"
  dns_resolver_valid: 30
' > conf/config.yaml

make init

if ! grep "resolver 127.0.0.1 \[::1\]:5353 valid=30 ipv6=on;" conf/nginx.conf > /dev/null; then
    echo "failed: dns_resolver_valid doesn't take effect"
    exit 1
fi

echo '
apisix:
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - 9100
  dns_resolver:
    - 127.0.0.1
    - "[::1]:5353"
  dns_resolver_valid: 30
' > conf/config.yaml

make init

count=$(grep -c "resolver 127.0.0.1 \[::1\]:5353 valid=30 ipv6=on;" conf/nginx.conf)
if [ "$count" -ne 2 ]; then
    echo "failed: dns_resolver_valid doesn't take effect"
    exit 1
fi

echo "pass: dns_resolver_valid takes effect"

echo '
apisix:
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - 9100
  dns_resolver:
    - 127.0.0.1
    - "::1"
    - "[::2]"
' > conf/config.yaml

make init

count=$(grep -c "resolver 127.0.0.1 \[::1\] \[::2\] ipv6=on;" conf/nginx.conf)
if [ "$count" -ne 2 ]; then
    echo "failed: can't handle IPv6 resolver w/o bracket"
    exit 1
fi

echo "pass: handle IPv6 resolver w/o bracket"

# ipv6 config test
echo '
apisix:
  enable_ipv6: false
  dns_resolver:
    - 127.0.0.1
  dns_resolver_valid: 30
' > conf/config.yaml

make init

if ! grep "resolver 127.0.0.1 valid=30 ipv6=off;" conf/nginx.conf > /dev/null; then
    echo "failed: ipv6 config doesn't take effect"
    exit 1
fi

# check dns resolver address
echo '
apisix:
  dns_resolver:
    - 127.0.0.1
    - "fe80::21c:42ff:fe00:18%eth0"
' > conf/config.yaml

out=$(make init 2>&1 || true)

if ! echo "$out" | grep "unsupported DNS resolver"; then
    echo "failed: should check dns resolver is unsupported"
    exit 1
fi

if ! grep "resolver 127.0.0.1 ipv6=on;" conf/nginx.conf > /dev/null; then
    echo "failed: should skip unsupported DNS resolver"
    exit 1
fi

if grep "fe80::21c:42ff:fe00:18%eth0" conf/nginx.conf > /dev/null; then
    echo "failed: should skip unsupported DNS resolver"
    exit 1
fi

echo "passed: check dns resolver"

# dns resolver in stream subsystem
rm logs/error.log || true

echo "
apisix:
    enable_admin: true
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - addr: 9100
    dns_resolver:
        - 127.0.0.1:1053
nginx_config:
    error_log_level: info
" > conf/config.yaml

make run
sleep 0.5
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl -v -k -i -m 20 -o /dev/null -s -X PUT http://127.0.0.1:9180/apisix/admin/stream_routes/1 \
    -H "X-API-KEY: $admin_key" \
    -d '{
        "upstream": {
            "type": "roundrobin",
            "nodes": [{
                "host": "sd.test.local",
                "port": 1995,
                "weight": 1
            }]
        }
    }'

curl http://127.0.0.1:9100 || true
make stop
sleep 0.1 # wait for logs output

if grep -E 'dns client error: 101 empty record received while prereading client data' logs/error.log; then
    echo "failed: resolve upstream host in stream subsystem should works fine"
    exit 1
fi

if ! grep -E 'dns resolver domain: sd.test.local to 127.0.0.(1|2) while prereading client data' logs/error.log; then
    echo "failed: resolve upstream host in preread phase should works fine"
    exit 1
fi

echo "success: resolve upstream host in stream subsystem works fine"
