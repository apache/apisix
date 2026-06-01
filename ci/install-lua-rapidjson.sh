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

set -euo pipefail

RAPIDJSON_VERSION="${RAPIDJSON_VERSION:-0.7.2}"
ROCKSPEC_VERSION="${ROCKSPEC_VERSION:-0.7.2-1}"
LUAROCKS_BIN="${LUAROCKS:-luarocks}"
TREE="${1:-}"

if [ -n "${TREE}" ]; then
    mkdir -p "${TREE}"
    TREE="$(cd "${TREE}" && pwd)"
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

cd "${workdir}"
"${LUAROCKS_BIN}" unpack rapidjson "${RAPIDJSON_VERSION}"
cd "rapidjson-${ROCKSPEC_VERSION}/lua-rapidjson"

# lua-rapidjson enables -march=native by default, which can leak CI CPU
# features into the shipped rapidjson.so.
sed -i '/add_compile_options(-march=native)/d' CMakeLists.txt

if [ -n "${TREE}" ]; then
    "${LUAROCKS_BIN}" make "rapidjson-${ROCKSPEC_VERSION}.rockspec" --tree="${TREE}" --local
else
    "${LUAROCKS_BIN}" make "rapidjson-${ROCKSPEC_VERSION}.rockspec"
fi
