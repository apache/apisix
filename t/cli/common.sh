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

get_admin_key() {
    # First try to get the key from config.yaml
    local admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
    echo "DEBUG: config.yaml admin_key: '$admin_key'" >&2
    # If the key is empty (auto-generated), extract it from logs
    if [ -z "$admin_key" ] || [ "$admin_key" = "''" ] || [ "$admin_key" = "null" ]; then
        echo "DEBUG: Admin key is empty, looking for auto-generated key in logs..." >&2
        # Wait a bit for logs to be written
        sleep 3
        # Try multiple log locations and patterns
        for log_file in "logs/error.log" "/usr/local/apisix/logs/error.log"; do
            if [ -f "$log_file" ]; then
                echo "DEBUG: Checking log file: $log_file" >&2
                # Method 1: Look for the specific warning message pattern (get the LAST key, not first)
                admin_key=$(grep -A 10 "Generated admin keys for this session:" "$log_file" 2>/dev/null | grep -E "^  [A-Za-z0-9]{32}$" | tail -1 | sed 's/^  //' || true)
                if [ -n "$admin_key" ]; then
                    echo "DEBUG: Found admin key using method 1: $admin_key" >&2
                    break
                fi
                # Method 2: Look for any 32-character alphanumeric string that looks like a key (get the LAST one)
                admin_key=$(grep -o "[A-Z][A-Za-z0-9]\{31\}" "$log_file" 2>/dev/null | tail -1 || true)
                if [ -n "$admin_key" ]; then
                    echo "DEBUG: Found admin key using method 2: $admin_key" >&2
                    break
                fi
                # Method 3: Look for any pattern that might be an admin key (get the LAST one)
                admin_key=$(grep -o "[A-Za-z0-9]\{32\}" "$log_file" 2>/dev/null | tail -1 || true)
                if [ -n "$admin_key" ]; then
                    echo "DEBUG: Found admin key using method 3: $admin_key" >&2
                    break
                fi
                echo "DEBUG: No admin key found in $log_file" >&2
                echo "DEBUG: Last 20 lines of $log_file:" >&2
                tail -20 "$log_file" 2>/dev/null | head -10 >&2 || true
            else
                echo "DEBUG: Log file $log_file does not exist" >&2
            fi
        done
        if [ -z "$admin_key" ]; then
            echo "DEBUG: Could not find auto-generated admin key in any log file" >&2
            echo "DEBUG: Available log files:" >&2
            ls -la logs/ 2>/dev/null >&2 || true
            ls -la /usr/local/apisix/logs/ 2>/dev/null >&2 || true
        fi
    fi
    echo "$admin_key"
}

rm logs/error.log || true # clear previous error log
unset APISIX_PROFILE
