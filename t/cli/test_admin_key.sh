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

# test: comments preserved and key written without full config rewrite

git checkout conf/config.yaml

echo "
deployment:
    admin:
        admin_key:
            - name: admin
              key: '' # this comment should survive
              role: admin
" > conf/config.yaml

make run

# check comment is preserved
grep "this comment should survive" conf/config.yaml > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: comment was stripped from config.yaml"
    exit 1
fi
echo "passed: comment was preserved in config.yaml"

# check key was written to config.yaml
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
if [ -z "$admin_key" ] || [ "$admin_key" == "null" ] || [ "$admin_key" == "''" ]; then
    echo "failed: admin key was not written to config.yaml"
    exit 1
fi
echo "passed: generated admin key written to config.yaml"

# check warning log contains the generated key
grep "one or more admin keys were not set and have been auto-generated" logs/error.log > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: warning log not found"
    exit 1
fi
echo "passed: warning log emitted with auto-generated admin key"

make stop

git checkout conf/config.yaml

echo "
deployment:
    admin:
        admin_key:
            - name: admin
              key: '' # first key comment
              role: admin
            - name: admin2
              key: \"\" # second admin comment with double quotes
              role: admin
" > conf/config.yaml

make run

# check second key was written to config.yaml
admin_key1=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
if [ -z "$admin_key1" ] || [ "$admin_key1" == "null" ] || [ "$admin_key1" == "''" ]; then
    echo "failed: first admin key was not written to config.yaml"
    exit 1
fi
echo "passed: first generated admin key written to config.yaml"

# check second key was written to config.yaml
admin_key2=$(yq '.deployment.admin.admin_key[1].key' conf/config.yaml | sed 's/"//g')
if [ -z "$admin_key2" ] || [ "$admin_key2" == "null" ] || [ "$admin_key2" == "''" ]; then
    echo "failed: second admin key was not written to config.yaml"
    exit 1
fi
echo "passed: second generated admin key written to config.yaml"
