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

# check admin ui enabled

git checkout conf/config.yaml

make init

grep "location ^~ /ui/" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to enable embedded admin ui"
    exit 1
fi

make run

## check /ui redirects to /ui/

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/ui)
if [ ! $code -eq 301 ]; then
    echo "failed: failed to redirect /ui to /ui/"
    exit 1
fi

## check /ui/ accessible

mkdir -p ui/assets
echo "test_html" > ui/index.html
echo "test_js" > ui/assets/test.js
echo "test_css" > ui/assets/test.css

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/ui/)
if [ ! $code -eq 200 ]; then
    echo "failed: /ui/ not accessible"
    exit 1
fi

## check /ui/index.html accessible

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/ui/index.html)
if [ ! $code -eq 200 ]; then
    echo "failed: /ui/index.html not accessible"
    exit 1
fi

## check /ui/assets/test.js accessible

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/ui/assets/test.js)
if [ ! $code -eq 200 ]; then
    echo "failed: /ui/assets/test.js not accessible"
    exit 1
fi

## check /ui/assets/test.css accessible

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/ui/assets/test.css)
if [ ! $code -eq 200 ]; then
    echo "failed: /ui/assets/test.css not accessible"
    exit 1
fi

## check /ui/ single-page-application fallback

code=$(curl -v -k -i -m 20 -o /dev/null -s -w %{http_code} http://127.0.0.1:9180/ui/not_exist)
if [ ! $code -eq 200 ]; then
    echo "failed: /ui/not_exist not accessible"
    exit 1
fi

make stop

# test admin ui disabled

git checkout conf/config.yaml

echo "
deployment:
    admin:
        enable_admin_ui: false
" > conf/config.yaml

make init

grep "location ^~ /ui/" conf/nginx.conf > /dev/null
if [ $? -eq 0 ]; then
    echo "failed: failed to disable embedded admin ui"
    exit 1
fi
