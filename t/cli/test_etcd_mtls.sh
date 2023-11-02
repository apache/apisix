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

# The 'admin.apisix.dev' is injected by ci/common.sh@set_coredns

# etcd mTLS verify
echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
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
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
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
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
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

# etcd mTLS in stream subsystem
echo '
apisix:
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - addr: 9100
  ssl:
    ssl_trusted_certificate: t/certs/mtls_ca.crt
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
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

rm logs/error.log || true
make run
sleep 1
make stop

if grep "\[error\]" logs/error.log; then
    echo "failed: veirfy etcd certificate during sync should not fail"
fi

echo "passed: certificate verify in stream subsystem successfully"

# use host in etcd.host as sni by default
git checkout conf/config.yaml
echo '
apisix:
  ssl:
    ssl_trusted_certificate: t/certs/mtls_ca.crt
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "https://127.0.0.1:22379"
    prefix: "/apisix"
    tls:
      cert: t/certs/mtls_client.crt
      key: t/certs/mtls_client.key
  ' > conf/config.yaml

rm logs/error.log || true
make init
make run
sleep 1
make stop

if ! grep -F 'certificate host mismatch' logs/error.log; then
    echo "failed: should got certificate host mismatch when use host in etcd.host as sni"
    exit 1
fi


echo "passed: use host in etcd.host as sni by default"

# specify custom sni instead of using etcd.host
git checkout conf/config.yaml
echo '
apisix:
  ssl:
    ssl_trusted_certificate: t/certs/mtls_ca.crt
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "https://127.0.0.1:22379"
    prefix: "/apisix"
    tls:
      cert: t/certs/mtls_client.crt
      key: t/certs/mtls_client.key
      sni: "admin.apisix.dev"
  ' > conf/config.yaml

rm logs/error.log || true
make init
make run
sleep 1
make stop

if grep -E 'certificate host mismatch' logs/error.log; then
    echo "failed: should use specify custom sni"
    exit 1
fi

echo "passed: specify custom sni instead of using etcd.host"
