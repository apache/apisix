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

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="2025.7.1"
URL="https://github.com/modelcontextprotocol/servers/archive/refs/tags/${VERSION}.tar.gz"

WORKDIR="$(mktemp -d)"
DEST_DIR="${REPO_ROOT}/t/plugin/mcp/servers"

curl -L "${URL}" | tar -xz -C "${WORKDIR}"

rm -rf "${DEST_DIR}"
mkdir -p "$(dirname "${DEST_DIR}")"

cp -R "${WORKDIR}/servers-${VERSION}" "${DEST_DIR}"

(
  cd "${DEST_DIR}"
  npm install
  # Note: Although dlx specifies the package version, it does not use a lockfile, 
  # so dependency resolution is not reproducible. Only the package-lock.json included
  # in the release package can ensure that the entire dependency tree is fully locked.
  npm run build -w @modelcontextprotocol/server-filesystem
)

echo "[OK] filesystem MCP ready: ${DEST_DIR}"
