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

# test: @disable_proxy_buffering location is generated when proxy-buffering is enabled
echo '
plugins:
    - proxy-buffering
' > conf/config.yaml

make init

if ! grep "location @disable_proxy_buffering" conf/nginx.conf > /dev/null; then
    echo "failed: @disable_proxy_buffering location not found in nginx.conf when proxy-buffering is enabled"
    exit 1
fi
echo "passed: @disable_proxy_buffering location found when proxy-buffering is enabled"

if ! grep "proxy_buffering off" conf/nginx.conf > /dev/null; then
    echo "failed: proxy_buffering off not found in nginx.conf"
    exit 1
fi
echo "passed: proxy_buffering off found in nginx.conf"

# test: @disable_proxy_buffering location is NOT generated when proxy-buffering is not enabled
echo '
plugins: []
' > conf/config.yaml

make init

if grep "location @disable_proxy_buffering" conf/nginx.conf > /dev/null; then
    echo "failed: @disable_proxy_buffering location should not be in nginx.conf when proxy-buffering is not enabled"
    exit 1
fi
echo "passed: @disable_proxy_buffering location not generated when proxy-buffering is not enabled"
