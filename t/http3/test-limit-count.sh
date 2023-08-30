#!/usr/bin/env bash
set -euo pipefail
set -x

. $(dirname "$0")/common.sh

echo TEST 1: test if limit-count works

# configure apisix
ADMIN put /routes/1 -s -d '{
    "uri": "/httpbin/*",
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 5,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
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

# consume the quota
for ((i=0;i<2;i++)); do
    # send request
    REQ /httpbin/get -X GET --http3-only

    # validate the response headers
    GREP -ix "HTTP/3 200"
done

# no quota
REQ /httpbin/get -X GET --http3-only
GREP -x "HTTP/3 503"
GREP -ix "x-ratelimit-remaining: 0"

# wait for quota recovery
sleep 5

REQ /httpbin/get -X GET --http3-only
GREP -x "HTTP/3 200"
GREP -ix "x-ratelimit-remaining: 1"
