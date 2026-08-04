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

# Print the stream server{} block that contains "listen <port>", isolating
# it by brace-counting from each "server {".
block_with_listen() {
    awk -v port="$1" '
    /server[ \t]*\{/ { depth = 0; block = ""; inblock = 1 }
    inblock {
        block = block $0 "\n"
        depth += gsub(/\{/, "{")
        depth -= gsub(/\}/, "}")
        if (depth == 0) {
            if (block ~ ("listen " port "[ ;]")) { printf "%s", block }
            inblock = 0
        }
    }
    ' conf/nginx.conf
}

# Print the top-level stream{} block. `set_real_ip_from` is rendered into the
# http block too, so assertions about the stream side have to be scoped.
stream_block() {
    awk '
    /^stream[ \t]*\{/ { depth = 0; inblock = 1 }
    inblock {
        print
        depth += gsub(/\{/, "{")
        depth -= gsub(/\}/, "}")
        if (depth == 0) { inblock = 0 }
    }
    ' conf/nginx.conf
}

# Open a TCP connection to <port>, announce <claimed client ip> in a PROXY
# protocol v1 header, and print whatever comes back.
pp_request() {
    local port="$1"
    local claimed_ip="$2"
    exec 3<>/dev/tcp/127.0.0.1/"$port"
    printf 'PROXY TCP4 %s 127.0.0.1 56324 %s\r\n' "$claimed_ip" "$port" >&3
    timeout 3 cat <&3
    exec 3<&-
}

# === Default: no PROXY protocol anywhere ===
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - 9100
    udp:
      - 9200
' > conf/config.yaml
make init

if grep -E "listen 9100[ ;].*proxy_protocol" conf/nginx.conf > /dev/null; then
    echo "failed: tcp port should not accept PROXY protocol by default"
    exit 1
fi
if grep -E "proxy_protocol on;" conf/nginx.conf > /dev/null; then
    echo "failed: PROXY protocol to upstream should be off by default"
    exit 1
fi
echo "passed: default has no PROXY protocol"

# === Global enable_tcp_pp applies to every tcp port (accept side) ===
echo '
apisix:
  proxy_mode: "http&stream"
  proxy_protocol:
    enable_tcp_pp: true
  stream_proxy:
    tcp:
      - 9100
      - 9101
    udp:
      - 9200
' > conf/config.yaml
make init

if ! grep -E "listen 9100[ ;].*proxy_protocol" conf/nginx.conf > /dev/null; then
    echo "failed: global enable_tcp_pp should add proxy_protocol to 9100"
    exit 1
fi
if ! grep -E "listen 9101[ ;].*proxy_protocol" conf/nginx.conf > /dev/null; then
    echo "failed: global enable_tcp_pp should add proxy_protocol to 9101"
    exit 1
fi
if grep -E "listen 9200 udp.*proxy_protocol" conf/nginx.conf > /dev/null; then
    echo "failed: udp listen must not carry proxy_protocol"
    exit 1
fi
echo "passed: global enable_tcp_pp on every tcp port"

# === Per-port accept override beats the global default ===
echo '
apisix:
  proxy_mode: "http&stream"
  proxy_protocol:
    enable_tcp_pp: true
  stream_proxy:
    tcp:
      - addr: 9100
      - addr: 9101
        proxy_protocol: false
' > conf/config.yaml
make init

if ! grep -E "listen 9100[ ;].*proxy_protocol" conf/nginx.conf > /dev/null; then
    echo "failed: 9100 should inherit global enable_tcp_pp"
    exit 1
fi
if grep -E "listen 9101[ ;].*proxy_protocol" conf/nginx.conf > /dev/null; then
    echo "failed: 9101 should opt out of PROXY protocol"
    exit 1
fi
echo "passed: per-port accept override"

# === Per-port proxy_protocol_to_upstream splits into its own server block ===
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: 9100
      - addr: 9101
        proxy_protocol_to_upstream: true
    udp:
      - 9200
' > conf/config.yaml
make init

if [ "$(grep -c "proxy_protocol on;" conf/nginx.conf)" != "1" ]; then
    echo "failed: expected exactly one 'proxy_protocol on;' server block"
    exit 1
fi
if ! block_with_listen 9101 | grep -E "proxy_protocol on;" > /dev/null; then
    echo "failed: 9101 should be in the proxy_protocol-to-upstream block"
    exit 1
fi
if block_with_listen 9100 | grep -E "proxy_protocol on;" > /dev/null; then
    echo "failed: 9100 should be in the plain block"
    exit 1
fi
# 9100 and the udp 9200 share the same plain block
if ! block_with_listen 9100 | grep -E "listen 9200 udp" > /dev/null; then
    echo "failed: plain tcp and udp listens should share one server block"
    exit 1
fi
echo "passed: per-port proxy_protocol_to_upstream server block split"

# === Global enable_tcp_pp_to_upstream keeps udp out of the proxy_protocol block ===
echo '
apisix:
  proxy_mode: "http&stream"
  proxy_protocol:
    enable_tcp_pp_to_upstream: true
  stream_proxy:
    tcp:
      - 9100
      - 9101
    udp:
      - 9200
' > conf/config.yaml
make init

if [ "$(grep -c "proxy_protocol on;" conf/nginx.conf)" != "1" ]; then
    echo "failed: expected exactly one 'proxy_protocol on;' server block"
    exit 1
fi
if ! block_with_listen 9100 | grep -E "proxy_protocol on;" > /dev/null; then
    echo "failed: 9100 should send PROXY protocol upstream"
    exit 1
fi
if ! block_with_listen 9101 | grep -E "proxy_protocol on;" > /dev/null; then
    echo "failed: 9101 should send PROXY protocol upstream"
    exit 1
fi
if block_with_listen 9200 | grep -E "proxy_protocol on;" > /dev/null; then
    echo "failed: udp 9200 must not be in the proxy_protocol-to-upstream block"
    exit 1
fi
echo "passed: global enable_tcp_pp_to_upstream keeps udp separate"

# === Per-port proxy_protocol_to_upstream=false beats a global true default ===
echo '
apisix:
  proxy_mode: "http&stream"
  proxy_protocol:
    enable_tcp_pp_to_upstream: true
  stream_proxy:
    tcp:
      - addr: 9100
      - addr: 9101
        proxy_protocol_to_upstream: false
' > conf/config.yaml
make init

if ! block_with_listen 9100 | grep -E "proxy_protocol on;" > /dev/null; then
    echo "failed: 9100 should inherit global enable_tcp_pp_to_upstream"
    exit 1
fi
if block_with_listen 9101 | grep -E "proxy_protocol on;" > /dev/null; then
    echo "failed: 9101 should opt out of PROXY protocol to upstream"
    exit 1
fi
echo "passed: per-port proxy_protocol_to_upstream=false override"

# === A TLS port in the to-upstream group renders ssl in that block only ===
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: 9100
      - addr: 9101
        tls: true
        proxy_protocol_to_upstream: true
' > conf/config.yaml
make init

if ! block_with_listen 9101 | grep -E "ssl_certificate " > /dev/null; then
    echo "failed: tls port in the to-upstream block should render ssl_certificate"
    exit 1
fi
if ! block_with_listen 9101 | grep -E "proxy_protocol on;" > /dev/null; then
    echo "failed: 9101 should send PROXY protocol upstream"
    exit 1
fi
if block_with_listen 9100 | grep -E "ssl_certificate " > /dev/null; then
    echo "failed: the plain block must not render ssl_certificate"
    exit 1
fi
echo "passed: per-group ssl follows the TLS port into its server block"

# === No trusted addresses by default ===
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: 9100
        proxy_protocol: true
' > conf/config.yaml
make init

if stream_block | grep -E "set_real_ip_from" > /dev/null; then
    echo "failed: no address should be trusted by default"
    exit 1
fi
echo "passed: no set_real_ip_from by default"

# === stream.real_ip_from renders one set_real_ip_from per entry ===
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: 9100
        proxy_protocol: true
nginx_config:
  stream:
    real_ip_from:
      - 192.168.1.0/24
      - 10.0.0.0/8
' > conf/config.yaml
make init

if ! stream_block | grep -E "^\s*set_real_ip_from 192\.168\.1\.0/24;" > /dev/null; then
    echo "failed: stream.real_ip_from should render the trusted network"
    exit 1
fi
if ! stream_block | grep -E "^\s*set_real_ip_from 10\.0\.0\.0/8;" > /dev/null; then
    echo "failed: stream.real_ip_from should render every entry"
    exit 1
fi
echo "passed: stream.real_ip_from renders set_real_ip_from"

# === End to end: a trusted peer's PROXY header reaches the upstream ===
# The upstream is a PROXY-protocol-aware stream server that echoes the address
# it was told about, so this asserts on the header APISIX actually rebuilds
# rather than on what nginx.conf says.
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: 9100
        proxy_protocol: true
        proxy_protocol_to_upstream: true
nginx_config:
  stream:
    real_ip_from:
      - 127.0.0.1
  stream_configuration_snippet: |
    server {
        listen 9101 proxy_protocol;
        return "upstream saw $proxy_protocol_addr";
    }
' > conf/config.yaml
make run
wait_for_tcp 127.0.0.1 9180
wait_for_tcp 127.0.0.1 9100

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl -i http://127.0.0.1:9180/apisix/admin/stream_routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d \
    '{"upstream":{"nodes":{"127.0.0.1:9101":1},"type":"roundrobin"}}'

# Retry under a 10s deadline to cover etcd->stream-worker propagation.
ok=0
deadline=$(( $(date +%s) + 10 ))
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    if pp_request 9100 198.51.100.7 | grep -q "upstream saw 198.51.100.7"; then
        ok=1
        break
    fi
    sleep 0.3
done
set -x
if [ "$ok" -ne 1 ]; then
    echo "failed: upstream should see the client address, not the direct peer"
    exit 1
fi

make stop
echo "passed: trusted peer's client address reaches the upstream"

# === End to end: without a trusted peer the upstream sees the direct peer ===
echo '
apisix:
  proxy_mode: "http&stream"
  stream_proxy:
    tcp:
      - addr: 9100
        proxy_protocol: true
        proxy_protocol_to_upstream: true
nginx_config:
  stream_configuration_snippet: |
    server {
        listen 9101 proxy_protocol;
        return "upstream saw $proxy_protocol_addr";
    }
' > conf/config.yaml
make run
wait_for_tcp 127.0.0.1 9180
wait_for_tcp 127.0.0.1 9100

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl -i http://127.0.0.1:9180/apisix/admin/stream_routes/1 \
    -H "X-API-KEY: $admin_key" -X PUT -d \
    '{"upstream":{"nodes":{"127.0.0.1:9101":1},"type":"roundrobin"}}'

ok=0
deadline=$(( $(date +%s) + 10 ))
{ set +x; } 2>/dev/null
while [ "$(date +%s)" -lt "$deadline" ]; do
    if pp_request 9100 198.51.100.7 | grep -q "upstream saw 127.0.0.1"; then
        ok=1
        break
    fi
    sleep 0.3
done
set -x
if [ "$ok" -ne 1 ]; then
    echo "failed: an untrusted peer's claim must not be adopted"
    exit 1
fi

make stop
echo "passed: untrusted peer's claim is ignored"

echo "All stream PROXY protocol tests passed."
