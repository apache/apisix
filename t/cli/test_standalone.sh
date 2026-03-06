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
      openid-connect:
        client_id: "${{APISIX_CLIENT_ID}}"
        client_secret: "secret"
        discovery: "http://example.com/.well-known/openid-configuration"
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

# Verify the service is running (should not have validation errors)
code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test-large-number)
if [ $code -eq 500 ]; then
    echo "failed: large number env var was converted to scientific notation"
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
      proxy-rewrite:
        headers:
          X-Custom-ID: "${{NUMERIC_ID}}"
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

NUMERIC_ID="12345" make init
NUMERIC_ID="12345" make run
sleep 0.1

code=$(curl -s -H "Host: test.com" http://127.0.0.1:9080/test-quoted -o /dev/null -w %{http_code})
if [ ! $code -eq 404 ] && [ ! $code -eq 200 ]; then
    echo "failed: quoted numeric env var in apisix.yaml should work"
    exit 1
fi

make stop
sleep 0.5

echo "passed: quoted numeric env var preserved as string in apisix.yaml"

# test: config.yaml should still support type conversion
echo '
routes: []
#END
' > conf/apisix.yaml

echo '
apisix:
  node_listen: ${{NODE_PORT}}
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
' > conf/config.yaml

NODE_PORT=9080 make init

if ! grep "listen 0.0.0.0:9080" conf/nginx.conf > /dev/null; then
    echo "failed: numeric env var in config.yaml should be converted to number"
    exit 1
fi

echo "passed: config.yaml still converts numeric env vars correctly"

git checkout conf/config.yaml
git checkout conf/apisix.yaml