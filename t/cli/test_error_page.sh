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

git checkout conf/config.yaml
make run
sleep 0.1

# set route
code=$(curl -XPUT -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -d '{
    "uri": "/error_page",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    },
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions" : ["return function() if ngx.var.http_x_test_status ~= nil then;ngx.exit(tonumber(ngx.var.http_x_test_status));end;end"]
        }
    }
}')
if [ ! $code -eq 201 ]; then
    echo "failed: add route failed"
    exit 1
fi

sleep 0.1
# test 5xx html
for status in 500 502 503 504;
do
    resp=$(curl http://127.0.0.1:9080/error_page -H 'X-Test-Status: '${status})
    if [[ `echo $resp | grep -c "apisix.apache.org"` -eq '0' ]]; then
         echo "failed: the error page is not customized"
         exit 1
    fi
done

# test upstream 5xx
for status in 500 502 503 504;
do
    resp=$(curl http://127.0.0.1:9080/error_page -H 'X-Test-Upstream-Status: '${status})
    if [[ ! `echo $resp | grep -c "apisix.apache.org"` -eq '0' ]]; then
         echo "failed: the error page shouldn't be customized"
         exit 1
    fi
done


# delete the route
code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    echo "failed: delete route failed"
    exit 1
fi
