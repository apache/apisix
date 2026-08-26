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

# Writing a deployment section as YAML null makes merge_conf drop the default
# table, so anything reading through it has to be guarded. Both reads below used
# to die with a Lua stack trace instead of a configuration error.

echo '
apisix:
    node_listen: 9080
deployment:
    role: traditional
    role_traditional:
' > conf/config.yaml

out=$(make init 2>&1 || true)
if echo "$out" | grep -F "attempt to index"; then
    echo "failed: a null role_traditional should not raise a Lua error"
    exit 1
fi

echo "passed: a null role_traditional is tolerated"

echo '
apisix:
    node_listen: 9080
    enable_admin: true
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    admin:
    etcd:
        host:
            - http://127.0.0.1:2379
' > conf/config.yaml

out=$(make init 2>&1 || true)
if echo "$out" | grep -F "attempt to index"; then
    echo "failed: a null deployment.admin should not raise a Lua error"
    exit 1
fi

if ! echo "$out" | grep -F 'Please modify "admin_key" in conf/config.yaml'; then
    echo "failed: a null deployment.admin should report a missing admin key"
    exit 1
fi

echo "passed: a null deployment.admin reports a missing admin key"
