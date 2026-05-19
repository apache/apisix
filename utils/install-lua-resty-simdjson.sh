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

VERSION="${LUA_RESTY_SIMDJSON_VERSION:-v1.2.0}"
DEPS_DIR="${1:-deps}"

if [[ "${DEPS_DIR}" != /* ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    DEPS_DIR="${REPO_ROOT}/${DEPS_DIR}"
fi

LUA_DIR="${DEPS_DIR}/share/lua/5.1/resty/simdjson"
LIB_DIR="${DEPS_DIR}/lib/lua/5.1"
case "$(uname -s)" in
    Darwin)
        LIB_EXT="dylib"
        ;;
    *)
        LIB_EXT="so"
        ;;
esac
LIB_FILE="${LIB_DIR}/libsimdjson_ffi.${LIB_EXT}"
VERSION_FILE="${DEPS_DIR}/.lua-resty-simdjson-version"

if [[ -f "${LUA_DIR}/init.lua" && -f "${LIB_FILE}" && -f "${VERSION_FILE}" ]] \
   && grep -Fxq "${VERSION}" "${VERSION_FILE}"; then
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

git clone --depth 1 --branch "${VERSION}" https://github.com/Kong/lua-resty-simdjson.git "${TMP_DIR}/lua-resty-simdjson"

pushd "${TMP_DIR}/lua-resty-simdjson" >/dev/null
make build
mkdir -p "${LUA_DIR}" "${LIB_DIR}"
cp lib/resty/simdjson/*.lua "${LUA_DIR}/"
cp "libsimdjson_ffi.${LIB_EXT}" "${LIB_FILE}"
printf '%s\n' "${VERSION}" > "${VERSION_FILE}"
popd >/dev/null
