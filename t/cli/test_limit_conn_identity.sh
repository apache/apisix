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

# Run in the same environment as the other CLI tests: real etcd and Redis,
# with APISIX started from the complete source tree in the current directory.
saved_config=$(mktemp)
cp conf/config.yaml "$saved_config"
cleanup() {
    status=$?
    if [ "$status" -ne 0 ]; then
        cat logs/error.log || true
    fi
    make stop || true
    cp "$saved_config" conf/config.yaml
    rm -f "$saved_config"
    exit "$status"
}
trap cleanup EXIT

python3 t/cli/limit_conn_identity.py --write-config
make init
# Isolate this test's startup/runtime log from previous CLI tests.
mkdir -p logs
: > logs/error.log
make run
python3 -u t/cli/limit_conn_identity.py "$@"
