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

exit_if_not_customed_nginx

# Check etcd tls verify failure
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
    use_grpc: true
    host:
      - "https://127.0.0.1:12379"
    prefix: "/apisix"
  ' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "certificate verify failed"; then
    echo "failed: apisix should echo \"certificate verify failed\""
    exit 1
fi

echo "passed: Show certificate verify failed info successfully"


# Check etcd tls without verification
git checkout conf/config.yaml

echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    use_grpc: true
    host:
      - "https://127.0.0.1:12379"
    prefix: "/apisix"
    tls:
      verify: false
  ' > conf/config.yaml

out=$(make init 2>&1 || true)
if echo "$out" | grep "certificate verify failed"; then
    echo "failed: apisix should not echo \"certificate verify failed\""
    exit 1
fi

echo "passed: Certificate verification successfully"
