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

# stream is only fully supported on the customed apisix-nginx-module build
exit_if_not_customed_nginx

# Nacos discovery picks its shared dict by subsystem (discovery/nacos/init.lua):
#     local dict_name = is_http and "nacos" or "nacos-stream"
# and init_worker() raises 'lua_shared_dict "nacos-stream" not configured' when
# the dict is missing. The `nacos-stream` dict must therefore be declared in the
# stream block, otherwise enabling nacos discovery with the stream subsystem on
# aborts the stream worker at startup.
echo '
apisix:
    proxy_mode: stream
    enable_admin: false
    stream_proxy:
        tcp:
            - addr: 9100
discovery:
    nacos:
        host:
            - "http://127.0.0.1:8848"
' > conf/config.yaml

make run
# wait until the stream worker accepts connections, which only happens after
# init_worker has run -- avoids a race where the log is grepped too early
wait_for_tcp 127.0.0.1 9100
make stop

# guard against a false pass if nginx never started for an unrelated reason
if grep -q "\[emerg\]" logs/error.log; then
    echo "failed: nginx did not start"
    cat logs/error.log
    exit 1
fi

if grep -q 'lua_shared_dict "nacos-stream" not configured' logs/error.log; then
    echo "failed: nacos-stream shared dict is not declared in the stream subsystem"
    exit 1
fi

echo "passed: nacos discovery initializes in the stream subsystem"
