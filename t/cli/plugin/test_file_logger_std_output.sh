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

# setup upstream server
echo '
nginx_config:
    main_configuration_snippet: |
        daemon off;
    http_configuration_snippet: |
        server {
            listen 15151;
            location / {
                return 201 "hello";
            }
        }
' > conf/config.yaml

make init

tmpout=$(mktemp)
make run > "$tmpout" &

sleep 0.2

curl -k -i http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
  "uri": "/mock",
  "methods": [
    "GET"
  ],
  "plugins": {
    "file-logger": {
      "path": "stdout"
    }
  },
  "upstream": {
    "nodes": [
      {
        "host": "127.0.0.1",
        "port": 15151,
        "weight": 1
      }
    ],
    "type": "roundrobin"
  }
}'

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9080/mock)
if [ ! $code -eq 201 ]; then
    echo "failed: check mock api failed"
    exit 1
fi

make stop
sleep 0.1
if [ `grep -c '"status":201' "$tmpout"` -ne '1' ]; then
    echo "failed: standard output of the file-logger plugin does not match expectations"
    cat "$tmpout"
    rm "$tmpout"
    exit 1
fi
rm "$tmpout"

echo "passed: the file-logger plugin produced the expected output"
