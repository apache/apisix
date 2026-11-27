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

set -euo pipefail
unset APISIX_PROFILE

runtime=$(openresty -V 2>&1)
if [[ ! "$runtime" =~ nginx\ version:\ (openresty|nginx)/([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    echo "Could not determine the Nginx version" >&2
    exit 1
fi
version=$(( BASH_REMATCH[2] * 1000000 + BASH_REMATCH[3] * 1000 + BASH_REMATCH[4] ))
if (( version < 1029004 )) || [[ "$runtime" != *"--with-http_v2_module"* ]]; then
    echo "Skipping HTTPS upstream HTTP/2 test. This runtime lacks native HTTP/2 proxying."
    exit 0
fi

root=$PWD
checkout=$(mktemp -d /tmp/apisix-upstream-http2-XXXXXXXX)
cleanup() {
    local status=$?
    if (( status != 0 )) && [ -f logs/error.log ]; then
        tail -n 50 logs/error.log >&2
    fi
    if [ -s logs/nginx.pid ]; then
        ./bin/apisix stop >/dev/null 2>&1 || true
    fi
    rm -rf -- "$checkout"
    exit "$status"
}
cd "$checkout"
trap cleanup EXIT

chmod 0755 "$checkout"
mkdir conf logs
ln -s "$root/apisix" apisix
ln -s "$root/bin" bin
if [ -d "$root/deps" ]; then
    ln -s "$root/deps" deps
fi
ln -s "$root/conf/mime.types" conf/mime.types

cat >conf/config.yaml <<YAML
apisix:
  node_listen:
    - ip: 127.0.0.1
      port: 19380
  enable_admin: false
  enable_control: false
  ssl:
    enable: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
plugins:
  - proxy-buffering
  - response-rewrite
stream_plugins: []
nginx_config:
  worker_processes: 1
  http_configuration_snippet: |
    server {
        listen 127.0.0.1:19343 ssl;
        http2 on;
        ssl_certificate $root/t/certs/mtls_server.crt;
        ssl_certificate_key $root/t/certs/mtls_server.key;
        location = /post {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.print(ngx.var.server_protocol, " ", ngx.req.get_method(),
                          " ", ngx.req.get_body_data())
            }
        }
        location / {
            default_type text/plain;
            return 200 "\$server_protocol \$request_uri \$http_x_probe";
        }
    }
YAML

cat >conf/apisix.yaml <<'YAML'
upstreams:
  - id: default-https
    scheme: https
    type: roundrobin
    pass_host: rewrite
    upstream_host: admin.apisix.dev
    nodes:
      "127.0.0.1:19343": 1
  - id: https-http2
    scheme: https
    http_version: "2"
    type: roundrobin
    pass_host: rewrite
    upstream_host: admin.apisix.dev
    nodes:
      "127.0.0.1:19343": 1
routes:
  - id: default
    uri: /default
    upstream_id: default-https
  - id: explicit
    uri: /explicit
    upstream_id: https-http2
    plugins:
      response-rewrite:
        headers:
          set:
            X-Proxy-Result: applied
  - id: unbuffered
    uri: /unbuffered
    upstream_id: https-http2
    plugins:
      proxy-buffering:
        disable_proxy_buffering: true
  - id: unbuffered-default
    uri: /unbuffered-default
    upstream_id: default-https
    plugins:
      proxy-buffering:
        disable_proxy_buffering: true
  - id: post
    uri: /post
    upstream_id: https-http2
  - id: invalid
    uri: /invalid
    upstream:
      scheme: http
      http_version: "2"
      type: roundrobin
      nodes:
        "127.0.0.1:19343": 1
YAML

# Dynamic TLS verification also requires the APISIX Runtime TLS APIs.
has_tls_api() {
    command -v resty >/dev/null && resty -e '
        local ok, upstream = pcall(require, "resty.apisix.upstream")
        if not ok or not (upstream.set_ssl_verify and upstream.set_ssl_trusted_store) then
            ngx.exit(1)
        end
    '
}

test_tls=0
if has_tls_api; then
    test_tls=1
    for policy in trusted untrusted; do
        ca_cert=mtls_ca.crt
        if [ "$policy" = untrusted ]; then
            ca_cert=crl_ca.crt
        fi
        cat >>conf/apisix.yaml <<YAML
  - id: $policy
    uri: /$policy
    upstream:
      scheme: https
      http_version: "2"
      type: roundrobin
      pass_host: rewrite
      upstream_host: admin.apisix.dev
      nodes:
        "127.0.0.1:19343": 1
      tls:
        verify: true
        ca_certs:
          - |
$(sed 's/^/            /' "$root/t/certs/$ca_cert")
YAML
    done
fi
echo '#END' >>conf/apisix.yaml

./bin/apisix start

response_matches() {
    local path=$1 expected=$2 body
    shift 2
    body=$(curl --noproxy '*' --silent --show-error --fail --max-time 5 \
        -H 'X-Probe: forwarded' "$@" "http://127.0.0.1:19380$path")
    if [ "$body" != "$expected" ]; then
        echo "$path expected '$expected', got '$body'" >&2
        return 1
    fi
    echo "passed: $path upstream received $body"
}

curl --noproxy '*' --silent --show-error --max-time 5 \
    --retry 5 --retry-connrefused --retry-delay 1 --output /dev/null \
    http://127.0.0.1:19380/default

response_matches '/default?attempt=1' 'HTTP/1.1 /default?attempt=1 forwarded'
response_matches '/explicit?attempt=1' 'HTTP/2.0 /explicit?attempt=1 forwarded'
response_matches '/default?attempt=2' 'HTTP/1.1 /default?attempt=2 forwarded'
response_matches '/explicit?attempt=2' 'HTTP/2.0 /explicit?attempt=2 forwarded'
response_matches '/unbuffered?attempt=1' 'HTTP/2.0 /unbuffered?attempt=1 forwarded'
response_matches '/unbuffered-default' 'HTTP/1.1 /unbuffered-default forwarded'
response_matches '/post' 'HTTP/2.0 POST probe body' --data 'probe body'

headers=$(curl --noproxy '*' --silent --show-error --fail --max-time 5 \
    --dump-header - --output /dev/null http://127.0.0.1:19380/explicit)
grep -iq '^X-Proxy-Result: applied' <<<"$headers"
echo 'passed: response-rewrite still runs for the HTTP/2 upstream'

status_code() {
    curl --noproxy '*' --silent --show-error --max-time 5 \
        --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:19380$1"
}

if (( test_tls )); then
    response_matches '/trusted' 'HTTP/2.0 /trusted forwarded'
    test "$(status_code /untrusted)" = 502
    grep -q 'upstream SSL certificate verify error' logs/error.log
    echo 'passed: HTTP/2 upstream rejects a certificate signed by an untrusted CA'
fi

test "$(status_code /invalid)" = 404
grep -q 'failed to check item data of \[routes\].*key: /routes/invalid' logs/error.log
echo 'passed: HTTP/2 configuration is rejected for a plain HTTP upstream'
