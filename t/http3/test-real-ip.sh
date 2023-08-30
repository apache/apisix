#!/usr/bin/env bash
set -euo pipefail
set -x

. $(dirname "$0")/common.sh

echo TEST 1: query args, real-ip plugin, response-rewrite plugin

# configure apisix
ADMIN put /routes/1 -s -d '{
    "uri": "/httpbin/get",
    "plugins": {
        "real-ip": {
            "source": "arg_realip",
            "trusted_addresses": ["127.0.0.0/24"]
        },
        "response-rewrite": {
            "headers": {
                "remote_addr": "$remote_addr",
                "remote_port": "$remote_port"
            }
        }
    },
    "upstream": {
        "scheme": "https",
        "type": "roundrobin",
        "nodes": {
            "nghttp2.org": 1
        }
    }
}'

# send request
REQ '/httpbin/get?realip=127.0.0.100:666' --ipv4 --http3-only

# validate the response headers
GREP -x "HTTP/3 200"
GREP -x "remote-addr: 127.0.0.100"
GREP -x "remote-port: 666"
