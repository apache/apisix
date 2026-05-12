#!/usr/bin/env bash

set -euo pipefail

# Admin API curl wrapper
# c [get|put|post|delete|...] <resource path> <any curl args> ...
c() {
    method=${1^^}
    resource=$2
    shift 2
    curl ${ADMIN_SCHEME:-http}://${ADMIN_IP:-127.0.0.1}:${ADMIN_PORT:-9180}/apisix/admin${resource} \
    -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X $method "$@"
}

c put /routes/1 -d '{
    "uri": "/*",
    "upstream": {
        "scheme": "http",
        "type": "roundrobin",
        "nodes": {
            "localhost:8080": 1
        }
    }
}'

timeout 10 python3 -u t/test_sse.py

c put /ssls/1 -d '{
    "cert": "'"$(<t/certs/server.crt)"'",
    "key": "'"$(<t/certs/server.key)"'",
    "snis": [
        "localhost"
    ]
}'

c put /routes/1 -d '{
    "uri": "/*",
    "plugins": {
        "proxy-buffering": {
            "disable_proxy_buffering": true
        }
    },
    "upstream": {
        "scheme": "https",
        "type": "roundrobin",
        "nodes": {
            "localhost:8080": 1
        }
    }
}'

timeout 10 python3 -u t/test_sse.py ssl
