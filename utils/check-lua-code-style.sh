#!/bin/sh

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

set -ex

luacheck -q apisix t/lib

find apisix -name '*.lua' -exec ./utils/lj-releng {} + > \
    /tmp/check.log 2>&1 || (cat /tmp/check.log && exit 1)

grep -E "ERROR.*.lua:" /tmp/check.log > /tmp/error.log | true
if [ -s /tmp/error.log ]; then
    echo "=====bad style====="
    cat /tmp/check.log
    exit 1
fi
