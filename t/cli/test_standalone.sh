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

# test: small numeric env vars in apisix.yaml should still be converted to number
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
    uri: /test-small-number
    plugins:
      response-rewrite:
        body: "hello"
        status_code: ${{REWRITE_STATUS}}
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

REWRITE_STATUS="200" make init

if ! REWRITE_STATUS="200" make run > output.log 2>&1; then
    cat output.log
    echo "failed: small numeric env var should be converted to number in apisix.yaml"
    exit 1
fi

sleep 0.1

code=$(curl -o /tmp/response_body -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-small-number)
body=$(cat /tmp/response_body)
if [ "$code" -ne 200 ]; then
    echo "failed: expected 200 for /test-small-number, but got: $code, body: $body"
    exit 1
fi

make stop
sleep 0.5

echo "passed: small numeric env var converted to number in apisix.yaml"

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

# test: numeric env vars for upstream weight and retries in apisix.yaml
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
    uri: /test-upstream-env
    plugins:
      proxy-rewrite:
        uri: /apisix/nginx_status
    upstream:
      nodes:
        "127.0.0.1:9091": ${{WEIGHT}}
      type: roundrobin
      retries: ${{RETRIES}}
#END
' > conf/apisix.yaml

WEIGHT="1" RETRIES="3" make init

if ! WEIGHT="1" RETRIES="3" make run > output.log 2>&1; then
    cat output.log
    echo "failed: numeric env vars for weight/retries should be converted to number"
    exit 1
fi

sleep 0.1

code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-upstream-env)
if [ "$code" -ne 200 ]; then
    echo "failed: expected 200 for /test-upstream-env, but got: $code"
    exit 1
fi

make stop
sleep 0.5

echo "passed: numeric env vars for upstream weight and retries converted to number in apisix.yaml"

# test: boolean env vars in apisix.yaml should be converted to boolean
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
    uri: /test-bool-env
    plugins:
      redirect:
        http_to_https: ${{REDIRECT_HTTPS}}
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

REDIRECT_HTTPS="true" make init

if ! REDIRECT_HTTPS="true" make run > output.log 2>&1; then
    cat output.log
    echo "failed: boolean env var should be converted to boolean in apisix.yaml"
    exit 1
fi

sleep 0.1

# If boolean conversion works, redirect plugin returns 301
code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-bool-env)
if [ "$code" -ne 301 ]; then
    echo "failed: expected 301 redirect for /test-bool-env, but got: $code"
    exit 1
fi

make stop
sleep 0.5

echo "passed: boolean env var converted to boolean in apisix.yaml"

# test: config.yaml should still support numeric type conversion
echo '
routes: []
#END
' > conf/apisix.yaml

echo '
apisix:
  resolver_timeout: ${{RESOLVER_TIMEOUT}}
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
' > conf/config.yaml

if ! RESOLVER_TIMEOUT=5 make init > output.log 2>&1; then
    cat output.log
    echo "failed: config.yaml should convert numeric env vars to number"
    exit 1
fi

echo "passed: config.yaml still converts numeric env vars correctly"

# test: small numeric env var inside quoted string should stay as string
# (the exact scenario from issue #12932 — key-auth key expects a string,
#  previously substituted numeric values were coerced to numbers and failed
#  schema validation)
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
    uri: /test-quoted-numeric
    plugins:
      key-auth: {}
      proxy-rewrite:
        uri: /apisix/nginx_status
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
consumers:
  -
    username: testuser
    plugins:
      key-auth:
        key: "${{TEST_KEY}}"
#END
' > conf/apisix.yaml

TEST_KEY="12345" make init

if ! TEST_KEY="12345" make run > output.log 2>&1; then
    cat output.log
    echo "failed: quoted numeric env var should stay string and pass schema validation"
    exit 1
fi

sleep 0.1

# With correct key header → 200
code=$(curl -o /dev/null -s -m 5 -w %{http_code} -H "apikey: 12345" http://127.0.0.1:9080/test-quoted-numeric)
if [ "$code" -ne 200 ]; then
    echo "failed: expected 200 with correct apikey, but got: $code"
    cat logs/error.log
    exit 1
fi

# Without header → 401
code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-quoted-numeric)
if [ "$code" -ne 401 ]; then
    echo "failed: expected 401 without apikey, but got: $code"
    exit 1
fi

make stop
sleep 0.5

echo "passed: quoted numeric env var preserved as string for key-auth consumer key"

# test: boolean env var inside quoted string should stay as string
# (previously a quoted "${{V}}" with V=true got post-parse coerced to a Lua
#  boolean, which failed schema validation for string-typed plugin fields)
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
    uri: /test-quoted-bool
    plugins:
      response-rewrite:
        body: "${{BODY_VAL}}"
        status_code: 200
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

BODY_VAL="true" make init

if ! BODY_VAL="true" make run > output.log 2>&1; then
    cat output.log
    echo "failed: quoted boolean env var should stay string"
    exit 1
fi

sleep 0.1

code=$(curl -o /tmp/response_body -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-quoted-bool)
body=$(cat /tmp/response_body)
if [ "$code" -ne 200 ]; then
    echo "failed: expected 200 for /test-quoted-bool, but got: $code, body: $body"
    exit 1
fi
if [ "$body" != "true" ]; then
    echo "failed: quoted bool env var was not preserved as string, got: $body"
    exit 1
fi

make stop
sleep 0.5

echo "passed: quoted boolean env var preserved as string in apisix.yaml"

# test: default value fallback still works for unset env var
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
    uri: /test-default-val
    plugins:
      response-rewrite:
        body: "hello"
        status_code: ${{UNSET_STATUS:=202}}
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

unset UNSET_STATUS
make init

if ! make run > output.log 2>&1; then
    cat output.log
    echo "failed: default value fallback should work"
    exit 1
fi

sleep 0.1

code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-default-val)
if [ "$code" -ne 202 ]; then
    echo "failed: expected 202 from default fallback, but got: $code"
    exit 1
fi

make stop
sleep 0.5

echo "passed: default value fallback (\${{VAR:=default}}) works"

# test: env var substitution inside a YAML key
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
    uri: /test-key-sub
    plugins:
      "${{PLUGIN_NAME}}":
        body: "key-sub-ok"
        status_code: 200
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

PLUGIN_NAME="response-rewrite" make init

if ! PLUGIN_NAME="response-rewrite" make run > output.log 2>&1; then
    cat output.log
    echo "failed: env var in YAML key should be substituted before parsing"
    exit 1
fi

sleep 0.1

code=$(curl -o /tmp/response_body -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-key-sub)
body=$(cat /tmp/response_body)
if [ "$code" -ne 200 ] || [ "$body" != "key-sub-ok" ]; then
    echo "failed: expected 200/key-sub-ok for /test-key-sub, got code: $code body: $body"
    exit 1
fi

make stop
sleep 0.5

echo "passed: env var substitution inside YAML key"

# test: missing env var (no default) should produce a clear startup error
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
    uri: /test-missing-var
    plugins:
      response-rewrite:
        body: "hello"
        status_code: ${{DEFINITELY_NOT_SET_VAR}}
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

unset DEFINITELY_NOT_SET_VAR
if make init > output.log 2>&1; then
    echo "failed: make init should fail when required env var is missing"
    cat output.log
    exit 1
fi

if ! grep "can't find environment variable DEFINITELY_NOT_SET_VAR" output.log > /dev/null; then
    echo "failed: expected missing-env-var error message in init output"
    cat output.log
    exit 1
fi

echo "passed: missing env var produces clear startup error"

git checkout conf/config.yaml
git checkout conf/apisix.yaml
