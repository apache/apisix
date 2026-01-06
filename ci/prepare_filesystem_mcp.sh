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
DEST_DIR="${REPO_ROOT}/t/plugin/filesystem"
LOCK_SRC="${REPO_ROOT}/t/plugin/mcp/assets/package-lock.json"

curl -L "${URL}" | tar -xz -C "${WORKDIR}"

rm -rf "${DEST_DIR}"
mkdir -p "$(dirname "${DEST_DIR}")"

cp -R "${WORKDIR}/servers-${VERSION}/src/filesystem" "${DEST_DIR}"

# lock deps
if [[ -f "${LOCK_SRC}" ]]; then
  cp "${LOCK_SRC}" "${DEST_DIR}/package-lock.json"
else
  echo "[WARN] package-lock.json not found: ${LOCK_SRC}"
fi

# force noEmit = false (insert after "compilerOptions": line)
sed -i '/"compilerOptions"[[:space:]]*:/a\
    "noEmit": false,' "${DEST_DIR}/tsconfig.json"

(
  cd "${DEST_DIR}"
  npm install
  npm run build
)

echo "[OK] filesystem MCP ready: ${DEST_DIR}"
