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

set -ex

# nacos service healthcheck
URI_LIST=(
  "http://nacos2:8848/nacos/v1/ns/service/list?pageNo=1&pageSize=2"
  "http://nacos2:8848/nacos/v1/ns/service/list?groupName=test_group&pageNo=1&pageSize=2"
  "http://nacos2:8848/nacos/v1/ns/service/list?groupName=DEFAULT_GROUP&namespaceId=test_ns&pageNo=1&pageSize=2"
  "http://nacos2:8848/nacos/v1/ns/service/list?groupName=test_group&namespaceId=test_ns&pageNo=1&pageSize=2"
)

for URI in "${URI_LIST[@]}"; do
  if [[ $(curl -s "${URI}" | grep "APISIX-NACOS") ]]; then
    continue
  else
    exit 1;
  fi
done


for IDX in {1..7..1}; do
  REQ_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://nacos-service${IDX}:18001/hello")
  if [ "${REQ_STATUS}" -ne "200" ]; then
    exit 1;
  fi
done
