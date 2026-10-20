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

# The http block of the generated nginx.conf enables open_file_cache, which the
# test-nginx based cases don't have. A disk cache entry removed by PURGE must not
# be served again from a file descriptor cached before the purge.

echo '
deployment:
  admin:
    admin_key_required: false
    admin_key: ~
nginx_config:
  worker_processes: 1
  http_configuration_snippet: |
    server {
        listen 1980;
        location / {
            return 200 "hello";
        }
    }
' > conf/config.yaml

rm -rf /tmp/disk_cache_one/*
make run
sleep 1

admin() {
    curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9180/apisix/admin$1 -X PUT -d "$2"
}

# prints the value of response header $1
header() {
    local name=$1
    shift
    curl -s -o /dev/null -D - "$@" | grep -i "^$name:" | awk '{print $2}' | tr -d '\r'
}

cache_status() {
    header apisix-cache-status "$@"
}

code=$(admin /routes/proxy-cache '{
    "uri": "/proxy-cache",
    "plugins": {
        "proxy-cache": {
            "cache_strategy": "disk"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}')
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
    echo "failed: unable to create the proxy-cache route"
    exit 1
fi
sleep 1

url=http://127.0.0.1:9080/proxy-cache
[ "$(cache_status $url)" = "MISS" ]
[ "$(cache_status $url)" = "HIT" ]
[ "$(curl -s -o /dev/null -w "%{http_code}" -X PURGE $url)" = "200" ]
status=$(cache_status $url)
if [ "$status" != "MISS" ]; then
    echo "failed: proxy-cache served a purged entry, cache status: $status"
    exit 1
fi

echo "passed: proxy-cache PURGE removes the cached entry"

code=$(admin /routes/graphql-proxy-cache '{
    "uri": "/graphql",
    "plugins": {
        "graphql-proxy-cache": {
            "cache_strategy": "disk"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}')
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
    echo "failed: unable to create the graphql-proxy-cache route"
    exit 1
fi

code=$(admin /routes/graphql-proxy-cache-purge '{
    "uri": "/apisix/plugin/graphql-proxy-cache/*",
    "plugins": {
        "public-api": {}
    }
}')
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
    echo "failed: unable to create the graphql-proxy-cache purge route"
    exit 1
fi
sleep 1

graphql() {
    header "$1" http://127.0.0.1:9080/graphql \
        -H "Content-Type: application/json" -d '{"query": "query{persons{id}}"}'
}

[ "$(graphql apisix-cache-status)" = "MISS" ]
[ "$(graphql apisix-cache-status)" = "HIT" ]
key=$(graphql apisix-cache-key)
[ "$(curl -s -o /dev/null -w "%{http_code}" -X PURGE \
    http://127.0.0.1:9080/apisix/plugin/graphql-proxy-cache/disk/graphql-proxy-cache/$key)" = "200" ]
status=$(graphql apisix-cache-status)
if [ "$status" != "MISS" ]; then
    echo "failed: graphql-proxy-cache served a purged entry, cache status: $status"
    exit 1
fi

echo "passed: graphql-proxy-cache PURGE removes the cached entry"
