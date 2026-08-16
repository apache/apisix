#!/bin/sh
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

set -eu

artifacts=/artifacts
run_id="qg-es-$(date +%s)-$$"
body='{"query":{"term":{"kind":"query-gateway"}}}'

log() {
    printf '%s trace=%s %s\n' "$(date -u +%FT%TZ)" "$1" "$2"
}

wait_for_apisix() {
    attempts=0
    until curl -sS "$APISIX_URL/" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 30 ]; then
            log "$run_id" "event=apisix_unavailable"
            exit 1
        fi
        sleep 1
    done
}

request() {
    name=$1
    method=$2
    expected_status=$3
    expected_cache=$4
    content_type=$5
    authorization=$6
    trace_id="$run_id-$name"
    headers="$artifacts/$name.headers"
    response="$artifacts/$name.body"

    set -- -H "X-Opaque-ID: $trace_id"
    if [ "$content_type" = present ]; then
        set -- "$@" -H 'Content-Type: application/json'
    else
        set -- "$@" -H 'Content-Type:'
    fi
    if [ "$authorization" = present ]; then
        set -- "$@" -H 'Authorization: Bearer integration-test'
    fi

    log "$trace_id" "event=client_request case=$name method=$method"
    status=$(curl -sS -D "$headers" -o "$response" -w '%{http_code}'         -X "$method" "$APISIX_URL/search" "$@" --data "$body")

    case "$expected_status" in
        4xx) case "$status" in 4*) ;; *) exit 1 ;; esac ;;
        *) [ "$status" = "$expected_status" ] ;;
    esac

    case "$expected_cache" in
        MISS|HIT) grep -qi "^Apisix-Cache-Status: $expected_cache" "$headers" ;;
        NONE) ! grep -qi '^Apisix-Cache-Status:' "$headers" ;;
    esac

    if [ "$expected_status" = 200 ]; then
        grep -q '"name":"integration"' "$response"
    fi

    printf '%s %s %s %s\n' "$trace_id" "$name" "$method" "$expected_cache" >> "$artifacts/requests"
    log "$trace_id" "event=client_response case=$name status=$status cache=$expected_cache"
}

curl -fsS -X PUT "$ELASTICSEARCH_URL/query-gateway-integration"     -H 'Content-Type: application/json'     -d '{"mappings":{"properties":{"kind":{"type":"keyword"}}}}' >/dev/null
curl -fsS -X POST "$ELASTICSEARCH_URL/query-gateway-integration/_doc/1"     -H 'Content-Type: application/json'     -d '{"kind":"query-gateway","name":"integration"}' >/dev/null
curl -fsS -X POST "$ELASTICSEARCH_URL/query-gateway-integration/_refresh" >/dev/null
curl -fsS -X PUT "$ELASTICSEARCH_URL/_cluster/settings"     -H 'Content-Type: application/json'     -d '{"transient":{"logger.org.elasticsearch.http.HttpTracer":"TRACE","logger.org.elasticsearch.http.HttpBodyTracer":"TRACE","http.tracer.include":"*"}}' >/dev/null

wait_for_apisix

# Cacheable QUERY and POST requests: first response populates, second reuses.
request query-miss QUERY 200 MISS present absent
request query-hit  QUERY 200 HIT  present absent
request post-miss  POST  200 MISS present absent
request post-hit   POST  200 HIT  present absent

# Credentials bypass cache; the repeated requests must remain uncached.
request query-auth-1 QUERY 200 NONE present present
request query-auth-2 QUERY 200 NONE present present
request post-auth-1  POST  200 NONE present present
request post-auth-2  POST  200 NONE present present

# Missing content type is rejected for cacheable QUERY and rejected upstream for POST.
request query-no-content-type QUERY 400 NONE absent absent
request post-no-content-type  POST  4xx NONE absent absent

printf '%s\n' "$run_id" > "$artifacts/run_id"
