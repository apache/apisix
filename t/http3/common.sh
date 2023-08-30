#!/usr/bin/env bash
set -euo pipefail
set -x

ADMIN() {
    method=${1^^};
    resource=$2;
    shift 2;
    curl ${ADMIN_SCHEME:-http}://${ADMIN_IP:-127.0.0.1}:${ADMIN_PORT:-9180}/apisix/admin${resource} \
        -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X $method "$@"
}

GREP() {
    grep "$@" ${tmpfile}-headers
}

GREP_BODY() {
    grep "$@" ${tmpfile}-body
}

JQ() {
    jq -e "$@" < ${tmpfile}-body
}

gc_fn_list=()

GC() {
    gc_fn_list+=("$@")
}

cleanup() {
    set +e
    for f in ${gc_fn_list[@]}; do
        $f
    done
    set -e
}

rm_tmpfile() {
    eval rm -f "${tmpfile}*"
}

GC rm_tmpfile

REQ() {
    rm_tmpfile
    curl https://localhost:9443"$@" -k -s -S -v -o ${tmpfile}-body 2>&1 | tee ${tmpfile}
    grep -E '^< \w+' ${tmpfile} | sed 's/< //g; s/ \r//g; s/\r//g' > ${tmpfile}-headers
}

if [[ ! -f ./logs/nginx.pid ]]; then
    ./bin/apisix start
    sleep 5
fi

tmpfile=$(mktemp)
trap cleanup EXIT INT TERM

ADMIN put /ssls/1 -d '{
    "cert": "'"$(<$(dirname "$0")/server.crt)"'",
    "key": "'"$(<$(dirname "$0")/server.key)"'",
    "snis": [
        "localhost"
    ]
}'
