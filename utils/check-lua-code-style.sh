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

luacheck -q lua

./utils/lj-releng lua/*.lua \
    lua/apisix/*.lua \
    lua/apisix/admin/*.lua \
    lua/apisix/core/*.lua \
    lua/apisix/http/*.lua \
    lua/apisix/http/router/*.lua \
    lua/apisix/plugins/*.lua \
    lua/apisix/plugins/grpc-transcode/*.lua \
    lua/apisix/plugins/limit-count/*.lua > \
    /tmp/check.log 2>&1 || (cat /tmp/check.log && exit 1)

sed -i 's/.*newproxy.*//g' /tmp/check.log
count=`grep -E ".lua:[0-9]+:" /tmp/check.log -c || true`

if [ $count -ne 0 ]
then
    cat /tmp/check.log
    exit 1
fi
