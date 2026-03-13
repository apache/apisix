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

standalone() {
    rm -f conf/apisix.yaml.link
    clean_up
    git checkout conf/apisix.yaml
}

trap standalone EXIT

# support environment variables in yaml values
echo '
apisix:
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
' > conf/config.yaml

echo '
routes:
  -
    uri: ${{var_test_path}}
    plugins:
      proxy-rewrite:
        uri: ${{var_test_proxy_rewrite_uri:=/apisix/nginx_status}}
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

# check for resolve variables
var_test_path=/test make init

if ! grep "env var_test_path;" conf/nginx.conf > /dev/null; then
    echo "failed: failed to resolve variables"
    exit 1
fi

# variable is valid
var_test_path=/test make run
sleep 0.1
code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test)
if [ ! $code -eq 200 ]; then
    echo "failed: resolve variables in apisix.yaml conf failed"
    exit 1
fi

echo "passed: resolve variables in apisix.yaml conf success"

# support environment variables in yaml keys
echo '
routes:
  -
    uri: "/test"
    plugins:
      proxy-rewrite:
        uri: "/apisix/nginx_status"
    upstream:
      nodes:
        "${{HOST_IP}}:${{PORT}}": 1
      type: roundrobin
#END
' > conf/apisix.yaml

# variable is valid
HOST_IP="127.0.0.1" PORT="9091" make init
HOST_IP="127.0.0.1" PORT="9091" make run
sleep 0.1

code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test)
if [ ! $code -eq 200 ]; then
    echo "failed: resolve variables in apisix.yaml conf failed"
fi

echo "passed: resolve variables in apisix.yaml conf success"

# configure standalone via deployment
echo '
deployment:
    role: data_plane
    role_data_plane:
       config_provider: yaml
' > conf/config.yaml

var_test_path=/test make run
sleep 0.1
code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes)
if [ ! $code -eq 404 ]; then
    echo "failed: admin API should be disabled automatically"
    exit 1
fi

echo "passed: admin API should be disabled automatically"

# support environment variables
echo '
routes:
  -
    uri: ${{var_test_path}}
    plugins:
      proxy-rewrite:
        uri: ${{var_test_proxy_rewrite_uri:=/apisix/nginx_status}}
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

var_test_path=/test make run
sleep 0.1
code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test)
if [ ! $code -eq 200 ]; then
    echo "failed: resolve variables in apisix.yaml conf failed"
    exit 1
fi

echo "passed: resolve variables in apisix.yaml conf success"

# Avoid unnecessary config reloads
## Wait for a second else `st_ctime` won't increase
sleep 1
expected_config_reloads=$(grep "config file $(pwd)/conf/apisix.yaml reloaded." logs/error.log | wc -l)

## Create a symlink to change the link count and as a result `st_ctime`
ln conf/apisix.yaml conf/apisix.yaml.link
sleep 1

actual_config_reloads=$(grep "config file $(pwd)/conf/apisix.yaml reloaded." logs/error.log | wc -l)
if [ $expected_config_reloads -ne $actual_config_reloads ]; then
    echo "failed: apisix.yaml was reloaded"
    exit 1
fi
echo "passed: apisix.yaml was not reloaded"

make stop
sleep 0.5

# test: environment variable with large number should be preserved as string
echo '
apisix:
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
' > conf/config.yaml

echo '
routes:
  -
    uri: /test-large-number
    plugins:
      response-rewrite:
        body: "${{APISIX_CLIENT_ID}}"
        status_code: 200
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

# Test with large number that exceeds Lua double precision
APISIX_CLIENT_ID="356002209726529540" make init

if ! APISIX_CLIENT_ID="356002209726529540" make run > output.log 2>&1; then
    cat output.log
    echo "failed: large number in env var should not cause type conversion error"
    exit 1
fi

sleep 0.1

# Verify the response body matches the exact large numeric string
code=$(curl -o /tmp/response_body -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-large-number)
body=$(cat /tmp/response_body)
if [ "$code" -ne 200 ]; then
    echo "failed: expected 200 for /test-large-number, but got: $code, body: $body"
    exit 1
fi
if [ "$body" != "356002209726529540" ]; then
    echo "failed: large number env var was not preserved as string, got: $body"
    exit 1
fi

make stop
sleep 0.5

echo "passed: large number in env var preserved as string in apisix.yaml"

# test: quoted numeric env vars in apisix.yaml should remain strings
echo '
apisix:
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
' > conf/config.yaml

echo '
routes:
  -
    uri: /test-quoted
    plugins:
      response-rewrite:
        body: "${{NUMERIC_ID}}"
        status_code: 200
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

NUMERIC_ID="12345" make init
NUMERIC_ID="12345" make run
sleep 0.1

code=$(curl -o /tmp/response_body -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-quoted)
body=$(cat /tmp/response_body)
if [ "$code" -ne 200 ]; then
    echo "failed: expected 200 for /test-quoted, but got: $code, body: $body"
    exit 1
fi
if [ "$body" != "12345" ]; then
    echo "failed: quoted numeric env var in apisix.yaml was not preserved as string, got: $body"
    exit 1
fi

make stop
sleep 0.5

echo "passed: quoted numeric env var preserved as string in apisix.yaml"

# test: config.yaml should still support type conversion (boolean)
echo '
routes: []
#END
' > conf/apisix.yaml

echo '
apisix:
  enable_admin: ${{ENABLE_ADMIN}}
deployment:
  role: traditional
  role_traditional:
    config_provider: yaml
  etcd:
    host:
      - "http://127.0.0.1:2379"
' > conf/config.yaml

ENABLE_ADMIN=false make init
ENABLE_ADMIN=false make run
sleep 0.1

# If type conversion works, enable_admin is boolean false and admin API is disabled (404)
# If type conversion fails, enable_admin stays string "false" which is truthy, admin API is enabled
code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes)
if [ "$code" -ne 404 ]; then
    echo "failed: expected 404 when admin API is disabled, but got: $code"
    exit 1
fi

make stop
sleep 0.5

echo "passed: config.yaml still converts boolean env vars correctly"

git checkout conf/config.yaml
git checkout conf/apisix.yaml
