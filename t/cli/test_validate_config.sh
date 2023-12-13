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
discovery:
    nacos:
        host: "127.0.0.1"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'property "host" validation failed: wrong type: expected array, got string'; then
    echo "failed: should check discovery schema during init"
    exit 1
fi

echo '
discovery:
    unknown:
        host: "127.0.0.1"
' > conf/config.yaml

if ! make init; then
    echo "failed: should ignore discovery without schema"
    exit 1
fi

echo "passed: check discovery schema during init"

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
deployment:
    admin:
        admin_listen:
            port: 9180
apisix:
    node_listen: 9080
    enable_admin: true
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - "localhost:9100"
        udp:
            - "127.0.0.1:9101"
' > conf/config.yaml

out=$(make run 2>&1 || echo "ouch")
if echo "$out" | grep 'ouch'; then
    echo "failed: allow configuring address in stream_proxy"
    exit 1
fi
make stop

echo "passed: allow configuring address in stream_proxy"

sed -i 's/^  \(node_listen:\)/  #\1/g' conf/config-default.yaml
sed -i 's/^    \(- 9080\)/    #\1/g' conf/config-default.yaml
sed -i 's/^  # \(node_listen: 9080\)/  \1/g' conf/config-default.yaml

echo '
apisix:
    node_listen:
      - 9080
      - 9081
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out"; then
    echo "failed: allow configuring node_listen as a number in the default config"
    exit 1
fi
git checkout conf/config-default.yaml

echo "passed: allow configuring node_listen as a number in the default config"

# apisix test
git checkout conf/config.yaml

out=$(./bin/apisix test 2>&1 || true)
if ! echo "$out" | grep "configuration test is successful"; then
    echo "failed: configuration test should be successful"
    exit 1
fi

echo "pass: apisix test"

./bin/apisix start
sleep 1 # wait for apisix starts

# set invalid configuration
echo '
nginx_config:
    main_configuration_snippet: |
        notexist on;
' > conf/config.yaml

# apisix restart
out=$(./bin/apisix restart 2>&1 || true)
if ! (echo "$out" | grep "\[emerg\] unknown directive \"notexist\"") && ! (echo "$out" | grep "APISIX is running"); then
    echo "failed: should restart failed when configuration invalid"
    exit 1
fi

echo "passed: apisix restart"

# apisix test - failure scenario
out=$(./bin/apisix test 2>&1 || true)
if ! echo "$out" | grep "configuration test failed"; then
    echo "failed: should test failed when configuration invalid"
    exit 1
fi

# apisix test failure should not affect apisix stop
out=$(./bin/apisix stop 2>&1 || true)
if echo "$out" | grep "\[emerg\] unknown directive \"notexist\""; then
    echo "failed: `apisix test` failure should not affect `apisix stop`"
    exit 1
fi

echo "passed: apisix test(failure scenario)"

# apisix plugin batch-requests real_ip_from invalid - failure scenario
echo '
plugins:
- batch-requests
nginx_config:
    http:
        real_ip_from:
        - "128.0.0.2"
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep "missing loopback or unspecified in the nginx_config.http.real_ip_from for plugin batch-requests"; then
    echo "failed: should check the realip configuration for batch-requests"
    exit 1
fi

echo "passed: apisix plugin batch-requests real_ip_from(failure scenario)"

# apisix plugin batch-requests real_ip_from valid
echo '
plugins:
- batch-requests
nginx_config:
    http:
        real_ip_from:
        - "127.0.0.1"
        - "127.0.0.2/8"
        - "0.0.0.0"
        - "0.0.0.0/0"
        - "::"
        - "::/0"
        - "unix:"
' > conf/config.yaml

out=$(make init 2>&1)
if echo "$out" | grep "missing loopback or unspecified in the nginx_config.http.real_ip_from for plugin batch-requests"; then
    echo "failed: should check the realip configuration for batch-requests"
    exit 1
fi

echo "passed: check the realip configuration for batch-requests"

echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - 127.0.0.1
' > conf/config.yaml

out=$(make init 2>&1 || true)
if ! echo "$out" | grep 'property "host" validation failed'; then
    echo "failed: should check etcd schema during init"
    exit 1
fi

echo "passed: check etcd schema during init"
