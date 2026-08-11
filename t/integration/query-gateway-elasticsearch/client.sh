#!/bin/sh
set -eu

artifacts=/artifacts
trace_id="qg-es-$(date +%s)-$$"
body='{"query":{"term":{"kind":"query-gateway"}}}'

log() {
    printf '%s trace=%s %s\n' "$(date -u +%FT%TZ)" "$trace_id" "$*"
}

wait_for_apisix() {
    attempts=0
    until curl -sS "$APISIX_URL/" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 30 ]; then
            log "event=apisix_unavailable"
            exit 1
        fi
        sleep 1
    done
}

curl -fsS -X PUT "$ELASTICSEARCH_URL/query-gateway-integration" \
    -H 'Content-Type: application/json' \
    -d '{"mappings":{"properties":{"kind":{"type":"keyword"}}}}' >/dev/null
curl -fsS -X POST "$ELASTICSEARCH_URL/query-gateway-integration/_doc/1" \
    -H 'Content-Type: application/json' \
    -d '{"kind":"query-gateway","name":"integration"}' >/dev/null
curl -fsS -X POST "$ELASTICSEARCH_URL/query-gateway-integration/_refresh" >/dev/null
curl -fsS -X PUT "$ELASTICSEARCH_URL/_cluster/settings" \
    -H 'Content-Type: application/json' \
    -d '{"transient":{"logger.org.elasticsearch.http.HttpTracer":"TRACE","logger.org.elasticsearch.http.HttpBodyTracer":"TRACE","http.tracer.include":"*"}}' >/dev/null

wait_for_apisix
log "event=client_request method=QUERY body=$body"
curl -fsS -D "$artifacts/first.headers" -o "$artifacts/first.body" \
    -X QUERY "$APISIX_URL/search" -H "X-Opaque-ID: $trace_id" \
    -H 'Content-Type: application/json' --data "$body"
grep -qi '^Apisix-Cache-Status: MISS' "$artifacts/first.headers"
grep -q '"name":"integration"' "$artifacts/first.body"
log "event=client_response attempt=1 cache=MISS"

curl -fsS -D "$artifacts/second.headers" -o "$artifacts/second.body" \
    -X QUERY "$APISIX_URL/search" -H "X-Opaque-ID: $trace_id" \
    -H 'Content-Type: application/json' --data "$body"
grep -qi '^Apisix-Cache-Status: HIT' "$artifacts/second.headers"
grep -q '"name":"integration"' "$artifacts/second.body"
printf '%s\n' "$trace_id" > "$artifacts/trace_id"
log "event=client_response attempt=2 cache=HIT"
