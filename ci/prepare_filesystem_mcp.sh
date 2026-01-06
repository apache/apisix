#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="2025.7.1"
URL="https://github.com/modelcontextprotocol/servers/archive/refs/tags/${VERSION}.tar.gz"

WORKDIR="$(mktemp -d)"
DEST_DIR="${REPO_ROOT}/t/plugin/filesystem"

curl -L "${URL}" | tar -xz -C "${WORKDIR}"

rm -rf "${DEST_DIR}"
mkdir -p "$(dirname "${DEST_DIR}")"
cp -R "${WORKDIR}/servers-${VERSION}/src/filesystem" "${DEST_DIR}"

# lock deps
sed -i -E 's/": *"\^/": "/g' "${DEST_DIR}/package.json"

# force noEmit = false (insert after "compilerOptions": line)
sed -i '/"compilerOptions"[[:space:]]*:/a\
    "noEmit": false,' "${DEST_DIR}/tsconfig.json"

(
  cd "${DEST_DIR}"
  npm install
  npm run build
)

echo "[OK] filesystem MCP ready: ${DEST_DIR}"