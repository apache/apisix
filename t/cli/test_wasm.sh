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

exit_if_not_customed_nginx

echo '
wasm:
    plugins:
        - name: wasm_log
          file: t/wasm/log/main.go.wasm
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'property "priority" is required'; then
    echo "failed: priority is required"
    exit 1
fi

echo '
wasm:
    plugins:
        - name: wasm_log
          priority: 888
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'property "file" is required'; then
    echo "failed: file is required"
    exit 1
fi

echo "passed: wasm configuration is validated"

echo '
wasm:
    plugins:
        - name: wasm_log
          priority: 7999
          file: t/wasm/log/main.go.wasm
  ' > conf/config.yaml

make init
if ! grep "wasm_vm " conf/nginx.conf; then
    echo "failed: wasm isn't enabled"
    exit 1
fi

echo "passed: wasm is enabled"
