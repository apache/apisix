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

# Reuse a scan for ordinary values, including after a leading comment.
unset YAML_SCAN_VALUE YAML_SCAN_MISSING YAML_SCAN_PREFIX
resty -I . -I deps/share/lua/5.1 -I deps/lib/lua/5.1 /dev/stdin <<'LUA'
local yaml = require("yaml")
local scanner = yaml.scanner
local scans = 0
yaml.scanner = function(text)
    scans = scans + 1
    return scanner(text)
end
local file = require("apisix.cli.file")
local lyaml = require("lyaml")
local resolved
for _, case in ipairs({
    {'"', "127.0.0.1"},
    {'"', "127.0.0.1:9091"},
    {"'", "127.0.0.1:9091"},
    {'"', "http://127.0.0.1:8080/path?q=1&x=2#fragment"},
    {"'", "http://127.0.0.1:8080/path?q=1&x=2#fragment"},
    {'"', "it's data: [one, two] # text"},
    {"'", 'a "quote" and C:\\path'},
    {'"', ""},
}) do
    for _, n in ipairs({32, 256, 1024}) do
        local parts = {"# header\nx:\n"}
        for i = 1, n do
            parts[#parts + 1] = '  - ' .. case[1] .. '${{YAML_SCAN_VALUE:=' .. case[2]
                .. '}}' .. case[1] .. ' # ${{YAML_SCAN_MISSING}}\n'
        end
        scans = 0
        resolved = assert(file.resolve_conf_var_in_text(table.concat(parts)))
        local result = lyaml.load(resolved)
        assert(#result.x == n)
        for _, value in ipairs(result.x) do
            assert(value == case[2])
        end
        assert(scans <= 2, "ordinary values must not rescan every prefix: " .. scans)
    end
end
assert(not (file.get_exported_vars() or {}).YAML_SCAN_MISSING)

-- A replacement can change whether later references belong to comments.
local cases = {
    {"a: ${{YAML_SCAN_VALUE:=ok}}\n${{YAML_SCAN_PREFIX:=#}} ${{YAML_SCAN_MISSING}}\nx: ok",
     "ok"},
    {"${{YAML_SCAN_PREFIX:=# }}${{YAML_SCAN_MISSING}}\nx: ok", "ok"},
    {"${{YAML_SCAN_PREFIX:=# header\nx:}} ${{YAML_SCAN_VALUE:=ok}}", "ok"},
    {"x: ${{YAML_SCAN_PREFIX:=|-}}\n  # ${{YAML_SCAN_VALUE:=ok}}", "# ok"},
    {'# header\nx: "${{YAML_SCAN_PREFIX:="}} # ${{YAML_SCAN_MISSING}}', ""},
    {'# header\nx: "${{YAML_SCAN_VALUE:=ok\n}}"', "ok"},
}
for _, case in ipairs(cases) do
    resolved = assert(file.resolve_conf_var_in_text(case[1]))
    assert(lyaml.load(resolved).x == case[2])
end
for _, newline in ipairs({"\194\133", "\226\128\168", "\226\128\169"}) do
    resolved = assert(file.resolve_conf_var_in_text(
        '# ${{YAML_SCAN_MISSING:=ignored' .. newline .. 'x}}: "${{YAML_SCAN_VALUE:=ok}}"'))
    assert(lyaml.load(resolved)["x}}"] == "ok")
end
print("passed: YAML scan reuse and syntax-changing substitutions")
LUA

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

if ! grep 'env "var_test_path";' conf/nginx.conf > /dev/null; then
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

# test: unset env vars referenced only in commented-out lines must be ignored
echo '
apisix:
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
' > conf/config.yaml

echo '
# ${{COMMENTED_UNSET_VAR}}
routes:
  -
    uri: /test-commented-var
    # indented comment: ${{ANOTHER_COMMENTED_UNSET_VAR}}
    plugins:
      response-rewrite:
        body: "${{COMMENT_BODY:=commented-ok}}"
        status_code: 200
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

unset COMMENTED_UNSET_VAR
unset ANOTHER_COMMENTED_UNSET_VAR
export COMMENT_BODY=commented-ok
make init

if ! make run > output.log 2>&1; then
    cat output.log
    echo "failed: make run should ignore env vars in commented-out lines"
    exit 1
fi

wait_for_commented_body() {
    local expected="$1"
    for ((i = 0; i < 100; i++)); do
        code=$(curl -o /tmp/response_body -s -m 1 -w '%{http_code}' \
            http://127.0.0.1:9080/test-commented-var) || true
        body=$(cat /tmp/response_body)
        if [ "$code" = 200 ] && [ "$body" = "$expected" ]; then
            return 0
        fi
        sleep 0.1
    done
    echo "failed: expected 200/$expected, got $code/$body"
    cat logs/error.log
    return 1
}

wait_for_commented_body "commented-ok"
master_pid=$(cat logs/nginx.pid)

# Change the file while the SAME instance runs. Allow the seconds-resolution
# mtime to advance, then atomically publish a complete file with its #END marker.
sleep 1.1
cat > conf/apisix.yaml.next <<'YAML'
# ${{COMMENTED_UNSET_VAR}}
routes:
  - uri: /test-commented-var # ${{ANOTHER_COMMENTED_UNSET_VAR}}
    plugins:
      response-rewrite:
        body: |- # ${{ANOTHER_COMMENTED_UNSET_VAR}}
          # ${{COMMENT_BODY
          }}
        status_code: 200
    upstream:
      nodes: {"127.0.0.1:9091": 1}
      type: roundrobin
#END
YAML
mv conf/apisix.yaml.next conf/apisix.yaml
wait_for_commented_body "# commented-ok"

test "$(cat logs/nginx.pid)" = "$master_pid"

make stop
sleep 0.5

echo "passed: YAML comments, block scalars, cross-line references and runtime reload"

git checkout conf/config.yaml
git checkout conf/apisix.yaml
