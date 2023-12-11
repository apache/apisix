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

# validate the apisix.yaml

. ./t/cli/common.sh

## apisix test
git checkout conf/config.yaml conf/apisix.yaml

echo '
apisix:
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
' > conf/config.yaml

out=$(./bin/apisix test 2>&1 || true)
if ! echo "$out" | grep "configuration test is successful"; then
    echo "failed: configuration test should be successful"
    exit 1
fi
echo "pass: apisix test"

# apisix bad plugin test
echo '
plugins:
 key: object
#END
' > conf/apisix.yaml

out=$(./bin/apisix test 2>&1 || true)
if ! echo "$out" | grep "apisix.plugin - failed" > /dev/null; then
    echo "failed: apisix.yaml test have failed as plugin should be a table"
    exit 1
fi
echo "pass: apisix.yaml - bad plugin test"

# apisix unknown plugin test
echo '
plugins:
 - name: unknown-plugin
#END
' > conf/apisix.yaml

out=$(./bin/apisix test 2>&1 || true)
if ! echo "$out" | grep "apisix.plugin - failed" > /dev/null; then
    echo "failed: apisix.yaml test have failed as plugin unknown-plugin is unknown"
    exit 1
fi
echo "pass: apisix.yaml - unknown plugin"

# apisix good plugin test
echo '
plugins:
 - name: proxy-rewrite
#END
' > conf/apisix.yaml

out=$(./bin/apisix test 2>&1 || true)
if ! echo "$out" | grep "apisix.plugin - valid" > /dev/null; then
    echo "failed: apisix.yaml test should be successful"
    exit 1
fi
echo "pass: apisix.yaml - good plugin"
