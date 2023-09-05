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
set -xeuo pipefail

if [ ! -f "./pack" ]; then
    wget -q https://github.com/buildpacks/pack/releases/download/v0.27.0/pack-v0.27.0-linux.tgz
    tar -zxvf pack-v0.27.0-linux.tgz
fi

# please update function-example/*/hello.go if you want to update function
./pack build test-uri-image --path ./ci/pod/openfunction/function-example/test-uri  --builder openfunction/builder-go:v2.4.0-1.17 --env FUNC_NAME="HelloWorld"  --env FUNC_CLEAR_SOURCE=true --env FUNC_GOPROXY="https://proxy.golang.org"
./pack build test-body-image --path ./ci/pod/openfunction/function-example/test-body --builder openfunction/builder-go:v2.4.0-1.17 --env FUNC_NAME="HelloWorld"  --env FUNC_CLEAR_SOURCE=true --env FUNC_GOPROXY="https://proxy.golang.org"
./pack build test-header-image --path ./ci/pod/openfunction/function-example/test-header  --builder openfunction/builder-go:v2.4.0-1.17 --env FUNC_NAME="HelloWorld"  --env FUNC_CLEAR_SOURCE=true --env FUNC_GOPROXY="https://proxy.golang.org"
