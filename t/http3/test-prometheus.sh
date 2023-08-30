#!/usr/bin/env bash
set -euo pipefail
set -x

. $(dirname "$0")/common.sh

echo TEST 1: test if prometheus works

# configure apisix
ADMIN put /routes/1 -s -d '{
    "uri": "/anything/*",
    "plugins": {
        "prometheus":{}
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "nghttp2.org": 1
        }
    }
}'

# send request
REQ /anything/foobar --http3-only

# validate the response headers
GREP -x "HTTP/3 404"

count_404() {
    curl http://127.0.0.1:9091/apisix/prometheus/metrics 2>&1 | \
        grep -F 'apisix_http_status{code="404",route="1",matched_uri="/anything/*"' | \
        awk '{print $2}'
}

# Wait for the counter value to be flushed to the shared dictionary
sleep 5
cnt1=$(count_404)

REQ /anything/foobar --http3-only

sleep 5
cnt2=$(count_404)

((cnt2 == cnt1 + 1))
