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

git checkout conf/config.yaml

exit_if_not_customed_nginx

# collect metrics run in privileged agent
rm logs/error.log || true

echo '
nginx_config:
  error_log_level: info
' > conf/config.yaml

make init
make run

curl -s -o /dev/null http://127.0.0.1:9091/apisix/prometheus/metrics

if ! grep -E "process type: privileged agent" logs/error.log; then
    echo "failed: prometheus works well in privileged agent"
    exit 1
fi

echo "prometheus works well in privileged agent successfully"
