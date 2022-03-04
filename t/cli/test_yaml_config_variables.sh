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

# check supported environment variables in apisix.yaml

yaml_config_variables_clean_up() {
    clean_up
    git checkout conf/apisix.yaml
}

trap yaml_config_variables_clean_up EXIT

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
    echo "failed: variable is not valid"
    exit 1
fi

echo "passed: resolve variables"
