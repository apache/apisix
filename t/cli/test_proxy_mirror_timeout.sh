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

echo '
plugin_attr:
  proxy-mirror:
    timeout:
        connect: 2000ms
        read: 2s
        send: 2000ms
' > conf/config.yaml

make init

if ! grep "proxy_connect_timeout 2000ms;" conf/nginx.conf > /dev/null; then
    echo "failed: proxy_connect_timeout not found in nginx.conf"
    exit 1
fi

if ! grep "proxy_read_timeout 2s;" conf/nginx.conf > /dev/null; then
    echo "failed: proxy_read_timeout not found in nginx.conf"
    exit 1
fi

echo "passed: proxy timeout configuration is validated"
