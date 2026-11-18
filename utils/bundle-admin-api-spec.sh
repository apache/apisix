#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

set -euo pipefail

task_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
task_repo_root=$(cd -- "${task_script_dir}/.." && pwd)
task_source="${task_repo_root}/docs/openapi/admin-api/openapi.yaml"
task_output="${1:-${task_repo_root}/docs/en/latest/admin-api.json}"
task_tmp_dir=$(mktemp -d)

cleanup() {
    rm -rf "${task_tmp_dir}"
}
trap cleanup EXIT

npx --yes @redocly/cli@2.72.1 bundle "${task_source}" \
    --output "${task_tmp_dir}/bundle.json" \
    --ext json

node -e '
const fs = require("node:fs");
const [input, output] = process.argv.slice(1);
const document = JSON.parse(fs.readFileSync(input, "utf8"));
fs.writeFileSync(output, JSON.stringify(document, null, 2) + "\n");
' "${task_tmp_dir}/bundle.json" "${task_output}"
