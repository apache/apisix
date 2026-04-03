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

# Test TCP port range (nginx native range syntax)
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "2000-2005"
' > conf/config.yaml

make init

if ! grep "listen 2000-2005" conf/nginx.conf > /dev/null; then
    echo "failed: TCP port range not found in nginx.conf"
    exit 1
fi

echo "passed: TCP port range"

# Test UDP port range
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - 9100
    udp:
      - "9300-9305"
' > conf/config.yaml

make init

if ! grep "listen 9300-9305 udp" conf/nginx.conf > /dev/null; then
    echo "failed: UDP port range not found in nginx.conf"
    exit 1
fi

echo "passed: UDP port range"

# Test address with port range
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "127.0.0.1:2000-2005"
' > conf/config.yaml

make init

if ! grep "listen 127.0.0.1:2000-2005" conf/nginx.conf > /dev/null; then
    echo "failed: address with port range not found in nginx.conf"
    exit 1
fi

echo "passed: address with port range"

# Test object form (table) with port range and TLS
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: "5000-5005"
        tls: true
' > conf/config.yaml

make init

if ! grep "listen 5000-5005.*ssl" conf/nginx.conf > /dev/null; then
    echo "failed: object form port range with TLS not found"
    exit 1
fi

echo "passed: object form port range with TLS"

# Test object form with address and port range
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: "127.0.0.1:3000-3005"
        tls: true
' > conf/config.yaml

make init

if ! grep "listen 127.0.0.1:3000-3005.*ssl" conf/nginx.conf > /dev/null; then
    echo "failed: object form address with port range and TLS not found"
    exit 1
fi

echo "passed: object form address with port range and TLS"

# Test mixed entries: ranges + individual ports + addresses coexist
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - 9100
      - "127.0.0.1:9101"
      - addr: 9102
        tls: true
      - "2000-2005"
      - addr: "3000-3005"
    udp:
      - 9200
      - "9300-9305"
' > conf/config.yaml

make init

if ! grep "listen 9100" conf/nginx.conf > /dev/null; then
    echo "failed: individual port 9100 not found"
    exit 1
fi
if ! grep "listen 127.0.0.1:9101" conf/nginx.conf > /dev/null; then
    echo "failed: address port 127.0.0.1:9101 not found"
    exit 1
fi
if ! grep "listen 9102.*ssl" conf/nginx.conf > /dev/null; then
    echo "failed: TLS port 9102 not found"
    exit 1
fi
if ! grep "listen 2000-2005" conf/nginx.conf > /dev/null; then
    echo "failed: range 2000-2005 not found"
    exit 1
fi
if ! grep "listen 3000-3005" conf/nginx.conf > /dev/null; then
    echo "failed: table form range 3000-3005 not found"
    exit 1
fi
if ! grep "listen 9200 udp" conf/nginx.conf > /dev/null; then
    echo "failed: UDP port 9200 not found"
    exit 1
fi
if ! grep "listen 9300-9305 udp" conf/nginx.conf > /dev/null; then
    echo "failed: UDP range 9300-9305 not found"
    exit 1
fi

echo "passed: mixed entries coexistence"

# Test backward compatibility
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: 9100
        tls: true
      - addr: "127.0.0.1:9101"
    udp:
      - 9200
      - "127.0.0.1:9201"
' > conf/config.yaml

make init

if ! grep "listen 9100.*ssl" conf/nginx.conf > /dev/null; then
    echo "failed: backward compat - TLS port 9100 not found"
    exit 1
fi
if ! grep "listen 127.0.0.1:9101" conf/nginx.conf > /dev/null; then
    echo "failed: backward compat - addr port not found"
    exit 1
fi
if ! grep "listen 9200 udp" conf/nginx.conf > /dev/null; then
    echo "failed: backward compat - UDP port 9200 not found"
    exit 1
fi
if ! grep "listen 127.0.0.1:9201 udp" conf/nginx.conf > /dev/null; then
    echo "failed: backward compat - UDP addr port not found"
    exit 1
fi

echo "passed: backward compatibility"

# === Negative test cases ===

# Invalid: port 0
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - 0
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "port out of range"; then
    echo "failed: port 0 should be rejected"
    exit 1
fi

echo "passed: reject port 0"

# Invalid: port 65536
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - 65536
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "port out of range"; then
    echo "failed: port 65536 should be rejected"
    exit 1
fi

echo "passed: reject port 65536"

# Invalid: float port (80.5 as YAML number — rejected by schema)
echo '
apisix:
  stream_proxy:
    tcp:
      - 80.5
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "failed to validate"; then
    echo "failed: float port 80.5 should be rejected"
    exit 1
fi

echo "passed: reject float port 80.5"

# Invalid: reversed range
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "3000-2000"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "invalid port range"; then
    echo "failed: reversed range 3000-2000 should be rejected"
    exit 1
fi

echo "passed: reject reversed range"

# Invalid: range with port 0
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "0-100"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "port out of range"; then
    echo "failed: range starting at 0 should be rejected"
    exit 1
fi

echo "passed: reject range with port 0"

# Invalid: range exceeding 65535
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "100-70000"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "port out of range"; then
    echo "failed: range exceeding 65535 should be rejected"
    exit 1
fi

echo "passed: reject range exceeding 65535"

# Invalid: addr with port out of range
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "127.0.0.1:0"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "port out of range"; then
    echo "failed: addr with port 0 should be rejected"
    exit 1
fi

echo "passed: reject addr with port 0"

# Invalid: addr with port exceeding 65535
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "127.0.0.1:65536"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "port out of range"; then
    echo "failed: addr with port 65536 should be rejected"
    exit 1
fi

echo "passed: reject addr with port 65536"

# Invalid: string "80.5"
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "80.5"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "invalid port format"; then
    echo "failed: string 80.5 should be rejected"
    exit 1
fi

echo "passed: reject string 80.5"

# Invalid: string "1e3"
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "1e3"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "invalid port format"; then
    echo "failed: string 1e3 should be rejected"
    exit 1
fi

echo "passed: reject string 1e3"

# Invalid: missing port
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - "127.0.0.1:"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "missing port"; then
    echo "failed: missing port in 127.0.0.1: should be rejected"
    exit 1
fi

echo "passed: reject missing port"

# Integration test: stream_route with port range (end-to-end traffic verification)
# Use nginx stream_configuration_snippet to create an inline upstream server
cat > conf/config.yaml << 'EOF'
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    only: false
    tcp:
      - "9100-9102"
deployment:
  admin:
    admin_key:
      - name: admin
        key: test-port-range-key
        role: admin
nginx_config:
  stream_configuration_snippet: |
    server {
        listen 9201;
        return "STREAM PORT RANGE OK\n";
    }
EOF

make run
sleep 1

# Create a stream route targeting the inline upstream
curl -k -i http://127.0.0.1:9180/apisix/admin/stream_routes/1 \
    -H 'X-API-KEY: test-port-range-key' -X PUT -d \
    '{"upstream":{"nodes":{"127.0.0.1:9201":1},"type":"roundrobin"}}'

sleep 1

# Verify traffic works on ports within the range
for port in 9100 9101; do
    if ! echo -e "" | nc -w 3 127.0.0.1 $port | grep "STREAM PORT RANGE OK"; then
        echo "failed: stream_route with port range - no response on port $port"
        check_failure
        exit 1
    fi
done

make stop

echo "passed: stream_route with port range (end-to-end)"

echo "All stream port range tests passed."
