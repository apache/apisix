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

# This file is like other test_*.sh, but requires extra dependencies which
# you don't need in daily development.

. ./t/cli/common.sh

# check error handling when connecting to old etcd
git checkout conf/config.yaml

echo '
etcd:
  host:
    - "http://127.0.0.1:3379"
  prefix: "/apisix"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'etcd cluster version 3.3.0 is less than the required version 3.4.0'; then
    echo "failed: properly handle the error when connecting to old etcd"
    exit 1
fi

echo "passed: properly handle the error when connecting to old etcd"

# It is forbidden to run apisix under the "/root" directory.
git checkout conf/config.yaml

mkdir /root/apisix

cp -r ./*  /root/apisix
cd /root/apisix
make init

out=$(make run 2>&1 || true)
if ! echo "$out" | grep "Error: It is forbidden to run APISIX in the /root directory"; then
    echo "failed: should echo It is forbidden to run APISIX in the /root directory"
    exit 1
fi

cd -

echo "passed: successfully prohibit APISIX from running in the /root directory"

rm -rf /root/apisix
