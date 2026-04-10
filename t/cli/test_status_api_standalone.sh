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
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
nginx_config:
  error_log_level: warn
apisix:
  status:
    ip: 127.0.0.1
    port: 7085
' > conf/config.yaml

echo '
routes:
  -
    uri: /get
    upstream:
      nodes:
        "httpbin.local:8280": 1
      type: roundrobin
#END
' > conf/apisix.yaml

# check for resolve variables
make run

sleep 0.5

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status/ready | grep 200 \
|| (echo "failed: status/ready api didn't return 200"; exit 1)

sleep 0.5

curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7085/status | grep 200 \
|| (echo "failed: status api didn't return 200"; exit 1)
