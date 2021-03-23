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

# 'make init' operates scripts and related configuration files in the current directory
# The 'apisix' command is a command in the /usr/local/apisix,
# and the configuration file for the operation is in the /usr/local/apisix/conf

. ./t/cli/common.sh

git checkout conf/config.yaml
make init

make run
sleep 0.1

# set route
code=$(curl -XPUT -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -d '{
    "uri": "/error_page",
    "plugins": {
        "serverless-pre-function": {
            "phase": "rewrite",
            "functions" : ["return function() local status = ngx.var.http_X_Test_Status ;ngx.exit(tonumber(status));end"]
        }
    }
}')
if [ ! $code -eq 200 ]; then
    echo "failed: add route failed"
    exit 1
fi

# test 5xx html
for status in 500 502 503 504;
do
    resp=$(curl http://127.0.0.1:9080/error_page -H 'X-Test-Status: '${status})
    if [[ `echo $resp | grep -c "apisix.apache.org"` -eq '0' ]]; then
         echo "failed: the error page is not customized"
         exit 1
    fi
done

# delete the route
code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    echo "failed: delete route failed"
    exit 1
fi
