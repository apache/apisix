#!/usr/bin/env bash
set -euo pipefail
set -x

script_path=$(dirname "$0")

. ${script_path}/common.sh

echo TEST 1: no client cert, ssl handshake failed

ADMIN put /routes/1 -d '
{
    "uri": "/*",
    "upstream": {
        "scheme": "https",
        "type": "roundrobin",
        "nodes": {
            "nghttp2.org": 1
        }
    }
}'

ADMIN put /ssls/1 -d '{
    "cert": "'"$(<${script_path}/server.crt)"'",
    "key": "'"$(<${script_path}/server.key)"'",
    "snis": [
        "localhost"
    ],
    "client": {
        "ca": "'"$(<${script_path}/ca.crt)"'",
        "depth": 10
    }
}'

sleep 1

set +e
REQ /httpbin/get --http3-only
err=$?
if [[ $err != 0 ]]; then
    echo "curl exit code: $err"
else
    echo "unexpected success..."
    exit 1
fi
set -e



echo TEST 2: route-level mtls, skip mtls

ADMIN put /ssls/1 -d '{
    "cert": "'"$(<${script_path}/server.crt)"'",
    "key": "'"$(<${script_path}/server.key)"'",
    "snis": [
        "localhost"
    ],
    "client": {
        "ca": "'"$(<${script_path}/ca.crt)"'",
        "depth": 10,
        "skip_mtls_uri_regex": [
            "/httpbin/get"
        ]
    }
}'

sleep 1

REQ /httpbin/get --http3-only

# validate the response headers
GREP -x "HTTP/3 200"

# validate the response body, e.g. JSON body
JQ '.headers["X-Forwarded-Host"] == "localhost"'



echo TEST 3: route-level mtls, not in whitelist, cannot skip mtls

set +e
REQ /httpbin/foobar --http3-only
set -e

# validate the response headers
GREP -x "HTTP/3 400"
