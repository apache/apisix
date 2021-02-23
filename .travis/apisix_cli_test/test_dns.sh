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

. ./.travis/apisix_cli_test/common.sh

# dns_resolver_valid
echo '
apisix:
  dns_resolver:
    - 127.0.0.1
    - "[::1]:5353"
  dns_resolver_valid: 30
' > conf/config.yaml

make init

if ! grep "resolver 127.0.0.1 \[::1\]:5353 valid=30;" conf/nginx.conf > /dev/null; then
    echo "failed: dns_resolver_valid doesn't take effect"
    exit 1
fi

echo '
apisix:
  stream_proxy:
    tcp:
      - 9100
  dns_resolver:
    - 127.0.0.1
    - "[::1]:5353"
  dns_resolver_valid: 30
' > conf/config.yaml

make init

count=$(grep -c "resolver 127.0.0.1 \[::1\]:5353 valid=30;" conf/nginx.conf)
if [ "$count" -ne 2 ]; then
    echo "failed: dns_resolver_valid doesn't take effect"
    exit 1
fi

echo "pass: dns_resolver_valid takes effect"
