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

echo "
apisix:
    enable_admin: false
    proxy_mode: stream
    stream_proxy:
        tcp:
            - addr: 9100
" > conf/config.yaml

make init

count=$(grep -c "lua_package_path" conf/nginx.conf)
if [ "$count" -ne 1 ]; then
    echo "failed: failed to enable stream proxy only by default"
    exit 1
fi

echo "passed: enable stream proxy only by default"

echo "
apisix:
    enable_admin: false
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - addr: 9100
" > conf/config.yaml

make init

count=$(grep -c "lua_package_path" conf/nginx.conf)
if [ "$count" -ne 2 ]; then
    echo "failed: failed to enable stream proxy and http proxy"
    exit 1
fi

echo "
apisix:
    enable_admin: true
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - addr: 9100
" > conf/config.yaml

make init

count=$(grep -c "lua_package_path" conf/nginx.conf)
if [ "$count" -ne 2 ]; then
    echo "failed: failed to enable stream proxy and http proxy when admin is enabled"
    exit 1
fi

echo "passed: enable stream proxy and http proxy"

echo "
apisix:
    ssl:
        ssl_trusted_certificate: t/certs/mtls_ca.crt
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - addr: 9100
" > conf/config.yaml

make init

if ! grep "t/certs/mtls_ca_combined.crt;" conf/nginx.conf > /dev/null; then
    echo "failed: failed to set trust certificate"
    exit 1
fi

echo "passed: set trust certificate"

echo "
apisix:
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - addr: 9100
stream_plugins:
    - ip-restriction
" > conf/config.yaml

make init

if grep "plugin-limit-conn-stream" conf/nginx.conf > /dev/null; then
    echo "failed: enable shdict on demand"
    exit 1
fi

echo "
apisix:
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - addr: 9100
stream_plugins:
    - limit-conn
" > conf/config.yaml

make init

if ! grep "plugin-limit-conn-stream" conf/nginx.conf > /dev/null; then
    echo "failed: enable shdict on demand"
    exit 1
fi

echo "passed: enable shdict on demand"
