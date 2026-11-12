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

# These tests only render configuration; they do not require etcd or bind ports.
set -eu

config_backup=$(mktemp)
cp conf/config.yaml "$config_backup"
trap 'cp "$config_backup" conf/config.yaml; rm -f "$config_backup"' EXIT

assert_listen() {
    if ! grep -Fq "listen $1" conf/nginx.conf; then
        echo "failed: missing listen $1"
        exit 1
    fi
}

assert_no_extra_ipv6() {
    for port in 9181 9092 7086 9093; do
        if grep -Eq "listen \\[::(1)?\\]:${port}[ ;]" conf/nginx.conf; then
            echo "failed: unexpected IPv6 listener on $port"
            exit 1
        fi
    done
}

# Defaults and explicitly configured default IPs both get an IPv6 counterpart.
# Use custom ports to ensure the IPv6 listener follows the configured port.
for ipv6 in true false; do
    for ip in default 127.0.0.1 127.0.0.2 '[::1]'; do
        admin_ip=$ip
        internal_ip=$ip
        if [ "$ip" = default ]; then
            admin_ip=''
            internal_ip=''
        elif [ "$ip" = 127.0.0.1 ]; then
            admin_ip=0.0.0.0
        fi
        admin_ip_config="ip: '$admin_ip'"
        internal_ip_config="ip: '$internal_ip'"
        if [ "$ip" = default ]; then
            admin_ip_config=''
            internal_ip_config=''
        fi
        cat > conf/config.yaml <<EOF
apisix:
  enable_ipv6: $ipv6
  enable_control: true
  control:
    $internal_ip_config
    port: 9092
  status:
    $internal_ip_config
    port: 7086
deployment:
  admin:
    admin_listen:
      $admin_ip_config
      port: 9181
plugin_attr:
  prometheus:
    enable_export_server: true
    export_addr:
      $internal_ip_config
      port: 9093
EOF
        ./bin/apisix init
        assert_listen "${admin_ip:-0.0.0.0}:9181;"
        assert_listen "${internal_ip:-127.0.0.1}:9092;"
        assert_listen "${internal_ip:-127.0.0.1}:7086 enable_process=privileged_agent;"
        assert_listen "${internal_ip:-127.0.0.1}:9093 reuseport;"
        if [ "$ip" = '[::1]' ]; then
            # An explicit IPv6 address remains the sole listener, even with IPv6 disabled.
            for port in 9181 9092 7086 9093; do
                [ "$(grep -Ec "listen .*:${port}[ ;]" conf/nginx.conf)" -eq 1 ]
            done
        elif [ "$ipv6" = true ] && { [ "$ip" = default ] || [ "$ip" = 127.0.0.1 ]; }; then
            assert_listen '[::]:9181;'
            assert_listen '[::1]:9092;'
            assert_listen '[::1]:7086 enable_process=privileged_agent;'
            assert_listen '[::1]:9093 reuseport;'
            for port in 9181 9092 7086 9093; do
                [ "$(grep -Ec "listen .*:${port}[ ;]" conf/nginx.conf)" -eq 2 ]
            done
        else
            assert_no_extra_ipv6
        fi
        echo "passed: internal listeners with enable_ipv6=$ipv6, ip=$ip"
    done
done

# TLS options must also apply to the additional Admin API listener.
cat > conf/config.yaml <<EOF
apisix:
  enable_ipv6: true
deployment:
  admin:
    https_admin: true
    admin_api_mtls:
      admin_ssl_cert: $PWD/t/certs/server.crt
      admin_ssl_cert_key: $PWD/t/certs/server.key
EOF
./bin/apisix init
assert_listen '0.0.0.0:9180 ssl;'
assert_listen '[::]:9180 ssl;'
assert_listen '[::1]:9090;'
echo 'passed: HTTPS admin and default control listeners'

# Stream-only deployments use a separate HTTP template for the exporter.
for ipv6 in true false; do
    cat > conf/config.yaml <<EOF
apisix:
  enable_ipv6: $ipv6
  proxy_mode: stream
  stream_proxy:
    tcp:
      - 9100
stream_plugins:
  - prometheus
plugin_attr:
  prometheus:
    enable_export_server: true
    export_addr:
      port: 9093
EOF
    ./bin/apisix init
    assert_listen '127.0.0.1:9093 reuseport;'
    if [ "$ipv6" = true ]; then
        assert_listen '[::1]:9093 reuseport;'
    else
        assert_no_extra_ipv6
    fi
    echo "passed: stream Prometheus with enable_ipv6=$ipv6"
done

# Disabling an endpoint must suppress both address families.
cat > conf/config.yaml <<EOF
apisix:
  enable_ipv6: true
  enable_admin: false
  enable_control: false
plugin_attr:
  prometheus:
    enable_export_server: false
EOF
./bin/apisix init
if grep -Eq 'listen .*:(9180|9090|7085|9091)[ ;]' conf/nginx.conf; then
    echo 'failed: disabled internal endpoint has a listener'
    exit 1
fi
echo 'passed: disabled internal endpoints'
