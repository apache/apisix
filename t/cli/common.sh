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

# 'make init' operates scripts and related configuration files in the current directory
# The 'apisix' command is a command in the /usr/local/apisix,
# and the configuration file for the operation is in the /usr/local/apisix/conf

set -ex

check_failure() {
    cat logs/error.log
}

clean_up() {
    if [ $? -gt 0 ]; then
        check_failure
    fi
    make stop || true
    git checkout conf/config.yaml
}

trap clean_up EXIT

exit_if_not_customed_nginx() {
    openresty -V 2>&1 | grep apisix-nginx-module || exit 0
}

# wait_for_tcp <host> <port> [timeout_secs]
# Poll until the port accepts TCP connections. Defaults to 10s.
# REQUIRES BASH — uses `local` and the `/dev/tcp` pseudo-device. All callers
# in t/cli/test_*.sh today use `#!/usr/bin/env bash`; the guard below fails
# fast with a clear message if this ever gets sourced from a non-bash shell,
# rather than producing a cryptic "no such file or directory" on /dev/tcp.
# The TCP probe runs entirely inside a subshell so the FD never enters the
# caller's file-descriptor table — this avoids accidentally closing a caller's
# FD 3 and keeps `set -e` safe.
# The polling loop runs with `set +x` to keep trace output quiet.
wait_for_tcp() {
    if [ -z "${BASH_VERSION:-}" ]; then
        echo "wait_for_tcp: requires bash (uses /dev/tcp and 'local')" >&2
        return 2
    fi
    local host="$1"
    local port="$2"
    local timeout="${3:-10}"
    local deadline=$(( $(date +%s) + timeout ))
    { set +x; } 2>/dev/null
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if (exec 3<>/dev/tcp/"$host"/"$port") 2>/dev/null; then
            set -x
            return 0
        fi
        sleep 0.1
    done
    set -x
    echo "wait_for_tcp: ${host}:${port} not accepting connections after ${timeout}s" >&2
    return 1
}

rm logs/error.log || true # clear previous error log
unset APISIX_PROFILE
