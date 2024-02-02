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

exit_if_not_customed_nginx

echo '
nginx_config:
  http:
    enable_access_log: false
' > conf/config.yaml

rm logs/error.log || true
make init
make run
sleep 0.1

curl -k -i http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "upstream": {
        "nodes": {
            "httpbin.org:80": 1
        },
        "type": "roundrobin"
    },
    "uri": "/get"
}'

sleep 0.1

curl -k -i http://127.0.0.1:9080/get

sleep 0.1

if ! grep "apisix_mirror_on_demand on;" conf/nginx.conf > /dev/null; then
    echo "failed: apisix_mirror_on_demand should on when running on apisix-runtime"
    exit 1
fi

if grep -E "invalid URL prefix" logs/error.log > /dev/null; then
    echo "failed: apisix_mirror_on_demand should on when running on apisix-runtime"
    exit 1
fi

echo "passed: apisix_mirror_on_demand is on when running on apisix-runtime"
