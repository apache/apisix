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

# enable dubbo
echo '
plugins:
    - dubbo-proxy
' > conf/config.yaml

make init

if ! grep "location @dubbo_pass " conf/nginx.conf > /dev/null; then
    echo "failed: dubbo location not found in nginx.conf"
    exit 1
fi

echo "passed: found dubbo location in nginx.conf"

# dubbo multiplex configuration
echo '
plugins:
    - dubbo-proxy
plugin_attr:
    dubbo-proxy:
        upstream_multiplex_count: 16
' > conf/config.yaml

make init

if ! grep "multi 16;" conf/nginx.conf > /dev/null; then
    echo "failed: dubbo multiplex configuration not found in nginx.conf"
    exit 1
fi

echo "passed: found dubbo multiplex configuration in nginx.conf"
