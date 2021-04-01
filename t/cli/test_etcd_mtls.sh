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

# The 'admin.apisix.dev' is injected by utils/set-dns.sh

# etcd mTLS verify
echo '
etcd:
  host:
    - "https://admin.apisix.dev:22379"
  prefix: "/apisix"
  tls:
    cert: t/certs/mtls_client.crt
    key: t/certs/mtls_client.key
    verify: false
  ' > conf/config.yaml

out=$(make init 2>&1 || echo "ouch")
if echo "$out" | grep "bad certificate"; then
    echo "failed: apisix should not echo \"bad certificate\""
    exit 1
fi

echo "passed: certificate verify success expectedly"

echo '
etcd:
  host:
    - "https://admin.apisix.dev:22379"
  prefix: "/apisix"
  tls:
    verify: false
  ' > conf/config.yaml

out=$(make init 2>&1 || echo "ouch")
if ! echo "$out" | grep "bad certificate"; then
    echo "failed: apisix should echo \"bad certificate\""
    exit 1
fi

echo "passed: certificate verify fail expectedly"

# etcd mTLS verify with CA
echo '
apisix:
  ssl:
    ssl_trusted_certificate: t/certs/mtls_ca.crt
etcd:
  host:
    - "https://admin.apisix.dev:22379"
  prefix: "/apisix"
  tls:
    cert: t/certs/mtls_client.crt
    key: t/certs/mtls_client.key
  ' > conf/config.yaml

out=$(make init 2>&1 || echo "ouch")
if echo "$out" | grep "certificate verify failed"; then
    echo "failed: apisix should not echo \"certificate verify failed\""
    exit 1
fi

if echo "$out" | grep "ouch"; then
    echo "failed: apisix should not fail"
    exit 1
fi

echo "passed: certificate verify with CA success expectedly"
