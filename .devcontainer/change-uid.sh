#!/bin/bash

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

set -exo pipefail

function change_uid() {
    local uid="$1"
    if [ -z "$uid" ]; then
        echo "Not changing user id"
        return 0
    fi
    local gid="${2:-$uid}"
    usermod --uid "$uid" --gid "$gid" "$USERNAME"
    chown -R "$uid:$gid" "/home/$USERNAME"
}

function change_gid() {
    local gid="$1"
    if [ -z "$gid" ]; then
        echo "Not changing group id"
        return 0
    fi
    groupmod --gid "$CHANGE_USER_GID" "$USERNAME"
}