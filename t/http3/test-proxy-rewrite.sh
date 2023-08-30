#!/usr/bin/env bash
set -euo pipefail
set -x

. $(dirname "$0")/common.sh

echo TEST 1: test basic config of proxy-rewrite plugin

# configure apisix
ADMIN put /routes/1 -s -d '{
    "uri": "/httpbin/*",
    "plugins": {
        "proxy-rewrite": {
          "headers": {
            "set": {
              "Accept-Encoding": "identity"
            }
          },
          "uri": "/httpbin/get",
          "host": "foo.bar"
        },                                                                                                                                                                      "serverless-pre-function": {                                                                                                                                                "phase": "access",                                                                                                                                                      "functions": [
                "return function(conf,ctx)
                    assert(ctx.var.http3 == \"h3\")
                end"
            ]
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
REQ /httpbin/anything --http3-only

# validate the response headers
GREP -x "HTTP/3 200"
GREP -F "server: APISIX/3"

# validate the response body, e.g. JSON body
GREP_BODY -F '"User-Agent": "curl/8.3.0-DEV"'
JQ '.headers.Host=="foo.bar"'
JQ '.url=="https://foo.bar/httpbin/get"'
