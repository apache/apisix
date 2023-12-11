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

set -e

check_failure() {
    cat logs/error.log
}

clean_up() {
    if [ $? -gt 0 ]; then
        check_failure
    fi
    make stop || true
    git checkout conf/config.yaml conf/apisix.yaml
}

trap clean_up EXIT

exit_if_not_customed_nginx() {
    openresty -V 2>&1 | grep apisix-nginx-module || exit 0
}

rm logs/error.log || true # clear previous error log
unset APISIX_PROFILE
