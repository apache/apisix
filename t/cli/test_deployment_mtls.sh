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

# use mTLS
# The 'admin.apisix.dev' is injected by ci/common.sh@set_coredns
echo '
deployment:
    role: control_plane
    role_control_plane:
        config_provider: etcd
        conf_server:
            listen: admin.apisix.dev:12345
            cert: t/certs/mtls_server.crt
            cert_key: t/certs/mtls_server.key
            client_ca_cert: t/certs/mtls_ca.crt
    etcd:
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
    certs:
        cert: t/certs/mtls_client.crt
        cert_key: t/certs/mtls_client.key
        trusted_ca_cert: t/certs/mtls_ca.crt
' > conf/config.yaml

make run
sleep 1

code=$(curl -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
make stop

if [ ! $code -eq 200 ]; then
    echo "failed: could not work with etcd"
    exit 1
fi

echo "passed: work well with etcd in control plane"

echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: control_plane
        control_plane:
            host:
            - "https://admin.apisix.dev:22379"
            prefix: "/apisix"
            timeout: 30
            tls:
                verify: false
    certs:
        cert: t/certs/mtls_client.crt
        cert_key: t/certs/mtls_client.key
        trusted_ca_cert: t/certs/mtls_ca.crt
' > conf/config.yaml

rm logs/error.log
make run
sleep 1

make stop

if grep '\[error\] .\+ https://admin.apisix.dev:22379' logs/error.log; then
    echo "failed: work well with control plane in data plane"
    exit 1
fi

echo "passed: work well with control plane in data plane"
