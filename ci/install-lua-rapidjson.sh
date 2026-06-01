#!/usr/bin/env bash

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
