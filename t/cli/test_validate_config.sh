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

# validate the config.yaml

. ./t/cli/common.sh

echo '
apisix:
  dns_resolver_valid: "/apisix"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'property "dns_resolver_valid" validation failed: wrong type: expected integer, got string'; then
    echo "failed: dns_resolver_valid should be a number"
    exit 1
fi

echo "passed: dns_resolver_valid should be a number"

echo '
apisix:
  ssl:
    ssl_trusted_certificate: t/certs/mtls_ca.crt
' > conf/config.yaml

out=$(make run 2>&1)
if echo "$out" | grep 'no such file'; then
    echo "failed: find the certificate correctly"
    exit 1
fi
make stop

echo "passed: find the certificate correctly"

echo '
apisix:
    node_listen: 9080
    enable_admin: true
    port_admin: 9180
    stream_proxy:
        tcp:
            - "localhost:9100"
        udp:
            - "127.0.0.1:9101"
' > conf/config.yaml

out=$(make run 2>&1 || echo "ouch")
if echo "$out" | grep 'ouch'; then
    echo "failed: allow configurating address in stream_proxy"
    exit 1
fi
make stop

echo "passed: allow configurating address in stream_proxy"
