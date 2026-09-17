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

. ./t/cli/common.sh

# openapi-to-mcp keeps its SSE sessions in the mcp-session shared dict, which
# is also what mcp-bridge uses. Enabling either one declares it.

echo '
plugins:
  - openapi-to-mcp
' > conf/config.yaml

make init

if ! grep "lua_shared_dict mcp-session 10m;" conf/nginx.conf > /dev/null; then
    echo "failed: openapi-to-mcp should declare the mcp-session shared dict"
    exit 1
fi

echo '
plugins:
  - echo
' > conf/config.yaml

make init

if grep "lua_shared_dict mcp-session" conf/nginx.conf > /dev/null; then
    echo "failed: mcp-session should not be declared when no MCP plugin is enabled"
    exit 1
fi

echo "passed: openapi-to-mcp declares the mcp-session shared dict"
