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

# Two, not one: the stream subsystem has no server of its own to export metrics
# from, so an http{} block is rendered to host the prometheus export server.
count=$(grep -c "lua_package_path" conf/nginx.conf)
if [ "$count" -ne 2 ]; then
    echo "failed: failed to enable stream proxy only by default"
    exit 1
fi

if grep "apisix.http_access_phase" conf/nginx.conf > /dev/null; then
    echo "failed: the http proxy is enabled in stream only mode"
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

# see the same check in t/cli/test_http_config.sh: the config file plugin list
# is only the boot-time default, so nginx.conf must not depend on it
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

if ! grep "plugin-limit-conn-stream" conf/nginx.conf > /dev/null; then
    echo "failed: shdict gated on the config file plugin list"
    exit 1
fi

echo "passed: shdict does not depend on the config file plugin list"
