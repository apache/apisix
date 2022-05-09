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

. ./t/cli/common.sh

# test cli operations
git checkout conf/config.yaml

make init

# apisix start - nginx.pid exists but no such process
fakepid=9999
echo $fakepid > logs/nginx.pid

out=$(make run 2>&1 || true)
if ! echo "$out" | grep "nginx.pid exists but there's no corresponding process with pid"; then
    echo "failed: can't check nginx.pid exists"
    exit 1
fi

make stop

echo "passed: make run(nginx.pid exists)"

# apisix start - running
out=$(make run; make run 2>&1 || true)
if ! echo "$out" | grep "APISIX is running"; then
    echo "failed: can't check APISIX running"
    exit 1
fi

make stop

echo "passed: make run(APISIX running)"
