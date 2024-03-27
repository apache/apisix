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

# The 'admin.apisix.dev' is injected by ci/common.sh@set_coredns
get_admin_key() {
    local admin_key=$(grep "key:" -A3 conf/config.yaml | grep "key: *" | awk '{print $2}')
    echo "$admin_key"
}
admin_key=$(get_admin_key); echo $admin_key

echo '
deployment:
    admin:
        admin_listen:
            port: 9180
        https_admin: true
        admin_api_mtls:
            admin_ssl_cert: "../t/certs/mtls_server.crt"
            admin_ssl_cert_key: "../t/certs/mtls_server.key"
            admin_ssl_ca_cert: "../t/certs/mtls_ca.crt"

' > conf/config.yaml

make run

sleep 1

# correct certs
code=$(curl -i -o /dev/null -s -w %{http_code}  --cacert ./t/certs/mtls_ca.crt --key ./t/certs/mtls_client.key --cert ./t/certs/mtls_client.crt -H "X-API-KEY: $admin_key" https://admin.apisix.dev:9180/apisix/admin/routes)
if [ ! "$code" -eq 200 ]; then
    echo "failed: failed to enabled mTLS for admin"
    exit 1
fi

# skip
code=$(curl -i -o /dev/null -s -w %{http_code} -k -H "X-API-KEY: $admin_key" https://admin.apisix.dev:9180/apisix/admin/routes)
if [ ! "$code" -eq 400 ]; then
    echo "failed: failed to enabled mTLS for admin"
    exit 1
fi

echo "passed: enabled mTLS for admin"
