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
nginx_config:
    max_pending_timers: 10240
    max_running_timers: 2561
" > conf/config.yaml

make init

count=$(grep -c "lua_max_pending_timers 10240;" conf/nginx.conf)
if [ "$count" -ne 1 ]; then
    echo "failed: failed to set lua_max_pending_timers"
    exit 1
fi

echo "passed: set lua_max_pending_timers successfully"

count=$(grep -c "lua_max_running_timers 2561;" conf/nginx.conf)
if [ "$count" -ne 1 ]; then
    echo "failed: failed to set lua_max_running_timers"
    exit 1
fi

echo "passed: set lua_max_running_timers successfully"

echo "
apisix:
    stream_proxy:
        tcp:
            - addr: 9100
nginx_config:
    max_pending_timers: 10240
    max_running_timers: 2561
" > conf/config.yaml

make init

count=$(grep -c "lua_max_pending_timers 10240;" conf/nginx.conf)
if [ "$count" -ne 1 ]; then
    echo "failed: failed to set lua_max_pending_timers in stream proxy"
    exit 1
fi

echo "passed: set lua_max_pending_timers successfully in stream proxy"

count=$(grep -c "lua_max_running_timers 2561;" conf/nginx.conf)
if [ "$count" -ne 1 ]; then
    echo "failed: failed to set lua_max_running_timers in stream proxy"
    exit 1
fi

echo "passed: set lua_max_running_timers successfully in stream proxy"
