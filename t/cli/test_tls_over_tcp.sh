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

 ./utils/create-ssl.py t/certs/mtls_server.crt t/certs/mtls_server.key test.com

curl -k -i http://127.0.0.1:9080/apisix/admin/stream_routes/1  \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d \
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
