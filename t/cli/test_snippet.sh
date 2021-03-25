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

# allow injecting configuration snippets

echo '
apisix:
    node_listen: 9080
    enable_admin: true
    port_admin: 9180
    stream_proxy:
        tcp:
            - 9100
nginx_config:
    main_configuration_snippet: |
        daemon on;
    http_configuration_snippet: |
        chunked_transfer_encoding on;
    http_server_configuration_snippet: |
        set $my "var";
    http_admin_configuration_snippet: |
        log_format admin "$request_time $pipe";
    http_end_configuration_snippet: |
        server_names_hash_bucket_size 128;
    stream_configuration_snippet: |
        tcp_nodelay off;
' > conf/config.yaml

make init

grep "daemon on;" -A 2 conf/nginx.conf | grep "configuration snippet ends" > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: can't inject main configuration"
    exit 1
fi

grep "chunked_transfer_encoding on;" -A 2 conf/nginx.conf | grep "configuration snippet ends" > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: can't inject http configuration"
    exit 1
fi

grep 'set $my "var";' -A 2 conf/nginx.conf | grep "configuration snippet ends" > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: can't inject http server configuration"
    exit 1
fi

grep 'log_format admin "$request_time $pipe";' -A 2 conf/nginx.conf | grep "configuration snippet ends" > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: can't inject admin server configuration"
    exit 1
fi

grep 'server_names_hash_bucket_size 128;' -A 2 conf/nginx.conf | grep "configuration snippet ends" > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: can't inject http end configuration"
    exit 1
fi

grep 'server_names_hash_bucket_size 128;' -A 3 conf/nginx.conf | grep "}" > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: can't inject http end configuration"
    exit 1
fi

grep 'tcp_nodelay off;' -A 2 conf/nginx.conf | grep "configuration snippet ends" > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: can't inject stream configuration"
    exit 1
fi

# use the builtin server by default

echo '
apisix:
    node_listen: 9080
nginx_config:
    http_configuration_snippet: |
        server {
            listen 9080;
            server_name qa.com www.qa.com;
            location / {
                return 503 "ouch";
            }
        }
' > conf/config.yaml

make run

sleep 1
code=$(curl -k -i -o /dev/null -s -w %{http_code} http://127.0.0.1:9080 -H 'Host: m.qa.com')
if [ ! $code -eq 404 ]; then
    echo "failed: use the builtin server by default"
    exit 1
fi
code=$(curl -k -i -o /dev/null -s -w %{http_code} http://127.0.0.1:9080 -H 'Host: www.qa.com')
if [ ! $code -eq 503 ]; then
    echo "failed: use the builtin server by default"
    exit 1
fi

make stop

echo "passed: use the builtin server by default"
