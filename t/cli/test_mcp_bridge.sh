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

# schema validation
echo '
apisix:
  node_listen: 1984
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
plugins:
  - mcp-bridge
' > conf/config.yaml

echo '
routes:
  -
    uri: /mcp/*
    plugins:
      mcp-bridge:
        base_uri: /mcp
        command: node
        args:
          - "t/plugin/mcp/servers/src/filesystem/dist/index.js"
          - "/"
#END
' > conf/apisix.yaml

make init
make stop || true
sleep 0.5
make run
sleep 1

# run the mcp client test
pushd t
if ! timeout 60 pnpm test plugin/mcp-bridge.spec.mts 2>&1; then
    echo "failed: mcp-bridge client test failed"
    popd
    exit 1
fi
popd

echo "passed: mcp-bridge client test"
