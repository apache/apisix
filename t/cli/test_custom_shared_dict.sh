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

# test: custom_lua_shared_dict in meta (global lua {} block, shared by http and stream)
git checkout conf/config.yaml

echo '
nginx_config:
  meta:
    custom_lua_shared_dict:
      my-global-dict: 1m
      another-global-dict: 5m
' > conf/config.yaml

make init

# The meta custom_lua_shared_dict should be rendered in the global lua {} block
if ! grep "lua_shared_dict my-global-dict 1m;" conf/nginx.conf > /dev/null; then
    echo "failed: meta custom_lua_shared_dict 'my-global-dict' not in nginx.conf"
    exit 1
fi

if ! grep "lua_shared_dict another-global-dict 5m;" conf/nginx.conf > /dev/null; then
    echo "failed: meta custom_lua_shared_dict 'another-global-dict' not in nginx.conf"
    exit 1
fi

echo "passed: meta custom_lua_shared_dict rendered in global lua {} block"

# test: custom_lua_shared_dict in stream {} block
git checkout conf/config.yaml

echo '
apisix:
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - addr: 9100
nginx_config:
  stream:
    custom_lua_shared_dict:
      my-stream-dict: 2m
      another-stream-dict: 8m
' > conf/config.yaml

make init

if ! grep "lua_shared_dict my-stream-dict 2m;" conf/nginx.conf > /dev/null; then
    echo "failed: stream custom_lua_shared_dict 'my-stream-dict' not in nginx.conf"
    exit 1
fi

if ! grep "lua_shared_dict another-stream-dict 8m;" conf/nginx.conf > /dev/null; then
    echo "failed: stream custom_lua_shared_dict 'another-stream-dict' not in nginx.conf"
    exit 1
fi

echo "passed: stream custom_lua_shared_dict rendered in stream {} block"

# test: meta and stream custom_lua_shared_dict together
git checkout conf/config.yaml

echo '
apisix:
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - addr: 9100
nginx_config:
  meta:
    custom_lua_shared_dict:
      shared-between-subsystems: 3m
  http:
    custom_lua_shared_dict:
      http-only-dict: 4m
  stream:
    custom_lua_shared_dict:
      stream-only-dict: 6m
' > conf/config.yaml

make init

if ! grep "lua_shared_dict shared-between-subsystems 3m;" conf/nginx.conf > /dev/null; then
    echo "failed: meta custom_lua_shared_dict 'shared-between-subsystems' not in nginx.conf"
    exit 1
fi

if ! grep "lua_shared_dict http-only-dict 4m;" conf/nginx.conf > /dev/null; then
    echo "failed: http custom_lua_shared_dict 'http-only-dict' not in nginx.conf"
    exit 1
fi

if ! grep "lua_shared_dict stream-only-dict 6m;" conf/nginx.conf > /dev/null; then
    echo "failed: stream custom_lua_shared_dict 'stream-only-dict' not in nginx.conf"
    exit 1
fi

echo "passed: meta, http, and stream custom_lua_shared_dict all rendered correctly"

# test: empty custom_lua_shared_dict should not break anything
git checkout conf/config.yaml

echo '
nginx_config:
  meta:
    custom_lua_shared_dict: {}
  stream:
    custom_lua_shared_dict: {}
' > conf/config.yaml

make init

echo "passed: empty custom_lua_shared_dict does not break init"
