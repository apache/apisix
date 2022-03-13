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

standalone() {
    clean_up
    git checkout conf/apisix.yaml
}

trap standalone EXIT

# support environment variables
echo '
apisix:
  enable_admin: false
  config_center: yaml
' > conf/config.yaml

echo '
routes:
  -
    uri: ${{var_test_path}}
    plugins:
      proxy-rewrite:
        uri: ${{var_test_proxy_rewrite_uri:=/apisix/nginx_status}}
    upstream:
      nodes:
        "127.0.0.1:9091": 1
      type: roundrobin
#END
' > conf/apisix.yaml

# check for resolve variables
var_test_path=/test make init

if ! grep "env var_test_path=/test;" conf/nginx.conf > /dev/null; then
    echo "failed: failed to resolve variables"
    exit 1
fi

# variable is valid
var_test_path=/test make run
sleep 0.1
code=$(curl -o /dev/null -s -m 5 -w %{http_code} http://127.0.0.1:9080/test)
if [ ! $code -eq 200 ]; then
    echo "failed: resolve variables in apisix.yaml conf failed"
    exit 1
fi

echo "passed: resolve variables in apisix.yaml conf success"

make stop

git checkout conf/config.yaml
git checkout conf/apisix.yaml

# support for having the port in the host header when pass_host = node and the port is not standard
echo '
apisix:
  enable_admin: false
  config_center: yaml

nginx_config:
  main_configuration_snippet: |
    daemon on;
  http_configuration_snippet: |
    server
    {
        listen 80;
        listen 1980;
        server_name _;
        access_log off;

        location /hello {
             return 200 $http_host;
        }
    }
' > conf/config.yaml

echo '
routes:
  -
    uri: /hello
    upstream:
      nodes:
        -
          host: 127.0.0.1
          port: 80
          weight: 1
          priority: -1
        -
          host: 127.0.0.1
          port: 1980
          weight: 1
      type: roundrobin
      pass_host: node
#END
' > conf/apisix.yaml

make init & make run

res=$(curl  http://127.0.0.1:9080/hello)
if [ "$res" != "127.0.0.1:1980" ];then
    echo "failed: have port in the host header when pass_host = node and the port is not standard failed"
    exit 1
fi

make stop

echo '
routes:
  -
    uri: /hello
    upstream:
      nodes:
        -
          host: 127.0.0.1
          port: 80
          weight: 1
        -
          host: 127.0.0.1
          port: 1980
          weight: 1
          priority: -1
      type: roundrobin
      pass_host: node
#END
' > conf/apisix.yaml

make init & make run

res=$(curl  http://127.0.0.1:9080/hello)
if [ "$res" != "127.0.0.1" ];then
    echo "failed: no port in host header when pass_host = node and port is standard failed"
    exit 1
fi

make stop

echo '
routes:
  -
    uri: /hello
    upstream:
      nodes:
        -
          host: 127.0.0.1
          port: 1982
          weight: 1
        -
          host: 127.0.0.1
          port: 1980
          weight: 1
          priority: -1
      type: roundrobin
      pass_host: node
      checks:
        active:
          http_path: /status
          healthy:
            interval: 1
            successes: 1
          unhealthy:
            interval: 1
            http_failures: 1
#END
' > conf/apisix.yaml

make init & make run

res=$(curl  http://127.0.0.1:9080/hello)
if [ "$res" != "127.0.0.1:1980" ];then
    echo "failed: on retry, have the port in host header when pass_host = node and port is not standard failed"
    exit 1
fi

echo "passed: have the port in the host header when pass_host = node and the port is not standard"

make stop







