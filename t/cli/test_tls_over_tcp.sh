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

# check tls over tcp proxy
echo "
apisix:
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - addr: 9100
              tls: true
nginx_config:
    stream_configuration_snippet: |
        server {
            listen 9101;
            return \"OK FROM UPSTREAM\";
        }

" > conf/config.yaml

make run
sleep 0.1

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
-H "X-API-KEY: $admin_key" -X PUT -d '
{
     "cert" : "'"$(cat t/certs/mtls_server.crt)"'",
     "key": "'"$(cat t/certs/mtls_server.key)"'",
     "snis": ["test.com"]
}'

admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
curl -k -i http://127.0.0.1:9180/apisix/admin/stream_routes/1  \
    -H "X-API-KEY: $admin_key" -X PUT -d \
    '{"upstream":{"nodes":{"127.0.0.1:9101":1},"type":"roundrobin"}}'

sleep 0.1
if ! echo -e 'mmm' | \
    openssl s_client -connect 127.0.0.1:9100 -servername test.com -CAfile t/certs/mtls_ca.crt \
        -ign_eof | \
    grep 'OK FROM UPSTREAM';
then
    echo "failed: should proxy tls over tcp"
    exit 1
fi

make stop
echo "passed: proxy tls over tcp"
