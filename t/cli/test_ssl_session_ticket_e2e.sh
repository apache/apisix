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

# APISIX nodes resume each other's TLS sessions with the shared session ticket
# keys: HTTPS and Stream (direct TLS, and the server that terminates a mixed
# `tls` + `tls_passthrough` listen), TLSv1.2 and TLSv1.3, with the keys of the
# Admin API (external) or of the built-in generator, in the traditional,
# control_plane + data_plane and standalone deployments, with both
# subsystems, Stream only and HTTP only.
#
# Node 0 runs from this directory, nodes 1 and 2 from copies of it. They share
# the etcd of the tests.

. ./t/cli/common.sh

exit_if_not_customed_nginx

if ! ssl_session_ticket_takeover; then
    echo "skipped: the runtime does not take over the session ticket keys"
    exit 0
fi

admin_key=edd1c9f034335f136f87ad84b625c8f1
record_key=/apisix/plugin_metadata/ssl-session-ticket
work=$(mktemp -d)
mkdir -p "$work/sess"

node_dir() {
    if [ "$1" = 0 ]; then
        echo "$PWD"
    else
        echo "$work/node$1"
    fi
}

https_port() { echo $(( 9443 + $1 )); }
tls_port() { echo $(( 9100 + 10 * $1 )); }
mixed_port() { echo $(( 9102 + 10 * $1 )); }
control_port() { echo $(( 9090 + ($1 > 0 ? $1 + 1 : 0) )); }
admin_port() { echo $(( 9180 + $1 )); }

for i in 1 2; do
    dir=$(node_dir $i)
    mkdir -p "$dir/logs" "$dir/t"
    cp -r apisix bin conf "$dir/"
    cp -r t/certs "$dir/t/"
    # a node id of its own
    rm -f "$dir/conf/apisix.uid"
    ln -s "$PWD/deps" "$dir/deps"
done
rm -f conf/apisix.uid

stop_node() {
    (cd "$(node_dir $1)" && ./bin/apisix stop) > /dev/null 2>&1 || true
}

# like clean_up of common.sh, for every node; whatever fails here, the exit
# status stays the one of the test
end() {
    local rc=$?
    set +e
    stop_node 1
    stop_node 2
    rm -rf "$work"
    if [ $rc -gt 0 ]; then
        check_failure
    fi
    make stop
    git checkout conf/config.yaml
}
trap end EXIT

# write_conf <node> <role> <key source> [proxy mode] [ssl_session_tickets]
# ENABLED=false disables the keys in the local policy
write_conf() {
    local i=$1 role=$2 source=$3 mode=${4:-http&stream} tickets=$5
    local provider=etcd encrypt=true admin=""
    if [ "$role" = standalone ]; then
        role=traditional
        provider=yaml
    fi
    if [ "$mode" = stream ]; then
        # no Admin API: the record is written to etcd in clear text
        encrypt=false
    fi
    # standalone with the Admin API would be the API-driven mode, which does
    # not read conf/apisix.yaml
    if [ "$role" != data_plane ] && [ "$mode" != stream ] && [ "$provider" = etcd ]; then
        admin="
    admin:
        admin_listen:
            port: $(admin_port $i)
        admin_key:
            - name: admin
              key: $admin_key
              role: admin"
    fi

    echo "
apisix:
    node_listen: $(( 9080 + i ))
    proxy_mode: $mode
    enable_admin: $([ -n "$admin" ] && echo true || echo false)
    ssl:
        listen:
            - port: $(https_port $i)
        ${tickets:+ssl_session_tickets: $tickets}
    stream_proxy:
        tcp:
            - addr: $(tls_port $i)
              tls: true
            - addr: $(mixed_port $i)
              tls: true
              tls_passthrough: true
    enable_control: true
    control:
        ip: 127.0.0.1
        port: $(control_port $i)
    data_encryption:
        enable_encrypt_fields: $encrypt
nginx_config:
    worker_processes: 2
deployment:
    role: $role
    role_$role:
        config_provider: $provider
$admin
plugin_attr:
    ssl-session-ticket:
        enabled: ${ENABLED:-true}
        key_source: $source
    prometheus:
        enable_export_server: false
" > "$(node_dir $i)/conf/config.yaml"
}

start_node() {
    (cd "$(node_dir $1)" && ./bin/apisix start)
    wait_for_tcp 127.0.0.1 "$(control_port $1)" 20
}

# a deterministic 80-byte key: the name ticket-name-<n>, then 64 bytes
key() {
    printf 'ticket-name-%04d%s' "$1" "$(printf '%064d' 0 | tr 0 K)" | base64 -w0
}

keys_json() {
    local list="" n
    for n in "$@"; do
        list="$list${list:+,}\"$(key "$n")\""
    done
    echo "[$list]"
}

admin_url="http://127.0.0.1:$(admin_port 0)"

# admin <method> <path> [body]: the response body, and fails the test on an
# error. Writes are paused for a while when the nodes have just changed
# their local policy: retried.
admin() {
    local method=$1 path=$2 body=$3
    local out code deadline=$(( $(date +%s) + 40 ))
    wait_for_tcp 127.0.0.1 "$(admin_port 0)" 20
    while true; do
        out=$(curl -sk -w '\n%{http_code}' -X "$method" "$admin_url/apisix/admin/$path" \
                   -H "X-API-KEY: $admin_key" ${body:+-d "$body"})
        code=${out##*$'\n'}
        out=${out%$'\n'*}
        if [ "$code" -lt 300 ]; then
            echo "$out"
            return 0
        fi
        if ! echo "$out" | grep -q 'writes are paused' || [ "$(date +%s)" -ge "$deadline" ]; then
            echo "failed: $method $path: $code $out" >&2
            exit 1
        fi
        sleep 1
    done
}

# the revision of the record of the keys
revision() {
    admin GET plugin_metadata/ssl-session-ticket | grep -o '"modifiedIndex":[0-9]*' \
        | grep -o '[0-9]*$'
}

# the JSON string of a file
json_file() {
    awk 'BEGIN { printf "\"" } { printf "%s\\n", $0 } END { printf "\"" }' "$1"
}

# the SSL object of test.com, and a stream route to etcd, which answers a
# plain HTTP request and closes the connection
setup_routes() {
    admin PUT ssls/1 "{\"cert\": $(json_file t/certs/apisix.crt), \
\"key\": $(json_file t/certs/apisix.key), \"snis\": [\"test.com\"]}"
    admin PUT stream_routes/1 \
        '{"upstream": {"nodes": {"127.0.0.1:2379": 1}, "type": "roundrobin"}}'
}

# wait_status <node> <status> [revision] [version]: until the node has
# converged to the status, on the record of the revision if given, with
# another local version than the given one
wait_status() {
    local i=$1 want=$2 rev=$3 old=$4
    # a change of the local policy pauses the policy nodes until all of them
    # have it, see their policy registry
    local deadline=$(( $(date +%s) + 60 ))
    { set +x; } 2>/dev/null
    while [ "$(date +%s)" -lt "$deadline" ]; do
        status="$(curl -s --max-time 2 "http://127.0.0.1:$(control_port $i)/v1/tls_session_ticket" \
                  || true)"
        if echo "$status" | grep -q "\"status\":\"$want\"" \
           && echo "$status" | grep -q '"fully_applied":true' \
           && { [ -z "$rev" ] || echo "$status" | grep -q "\"source_version\":\"$rev\""; } \
           && { [ -z "$old" ] || ! echo "$status" | grep -q "\"version\":\"$old\""; }
        then
            set -x
            return 0
        fi
        sleep 0.3
    done
    set -x
    echo "failed: node $i is not $want: $status"
    exit 1
}

# handshake <port> <1.2|1.3> <session out> [session in]: "New" or "Reused"
handshake() {
    local port=$1 version=$2 out=$3 in=$4
    local res
    res=$(printf 'GET / HTTP/1.0\r\nHost: test.com\r\n\r\n' \
          | timeout 10 openssl s_client -connect "127.0.0.1:$port" -servername test.com \
                "-tls${version/./_}" -ign_eof -sess_out "$out" ${in:+-sess_in "$in"} 2>&1 \
          | grep -Eo '^(New|Reused),' | head -n 1 | tr -d ,) || true
    echo "$res"
}

# the name of the key that encrypted the ticket of a saved session, if any
ticket_key() {
    openssl sess_id -in "$1" -noout -text 2>/dev/null | grep -A1 'TLS session ticket:' \
        | grep -Eo 'ticket-name-[0-9]{4}' || true
}

expect_eq() {
    if [ "$1" != "$2" ]; then
        echo "failed: $3: '$1', not '$2'"
        exit 1
    fi
}

# cross <from> <to> <port function> <version> <key n or "any">: a session of
# node from resumes on node to; leaves the session in $work/sess/last
cross() {
    local from=$1 to=$2 port=$3 version=$4 n=$5
    local s="$work/sess/$port-$version"
    expect_eq "$(handshake "$($port "$from")" "$version" "$s")" New "$port $version on $from"
    if [ "$n" != any ]; then
        expect_eq "$(ticket_key "$s")" "ticket-name-$(printf %04d "$n")" \
                  "key of the $port $version ticket of $from"
    fi
    expect_eq "$(handshake "$($port "$to")" "$version" "$s.2" "$s")" Reused \
              "$port $version session of $from on $to"
    cp "$s" "$work/sess/last"
}

listeners="https_port tls_port mixed_port"

# every listener, both versions, both directions
cross_all() {
    local a=$1 b=$2 n=$3 ports=${4:-$listeners} port version
    for port in $ports; do
        for version in 1.2 1.3; do
            cross "$a" "$b" "$port" "$version" "$n"
            cross "$b" "$a" "$port" "$version" "$n"
        done
    done
}


# traditional nodes, the keys of the Admin API; node 0 also serves the Admin
# API over HTTPS, with the native session tickets of nginx

etcdctl del "$record_key" > /dev/null
etcdctl del --prefix /apisix/stream_routes > /dev/null
write_conf 0 traditional external "http&stream" true
sed -i 's/^    admin:$/    admin:\
        https_admin: true\
        admin_api_mtls:\
            admin_ssl_cert: "..\/t\/certs\/apisix_admin_ssl.crt"\
            admin_ssl_cert_key: "..\/t\/certs\/apisix_admin_ssl.key"/' conf/config.yaml
write_conf 1 traditional external
start_node 0
start_node 1

admin_url="https://127.0.0.1:$(admin_port 0)"

setup_routes
# no keys yet: no stateless ticket
wait_status 0 off
wait_status 1 off
handshake "$(https_port 0)" 1.2 "$work/sess/none" > /dev/null
expect_eq "$(ticket_key "$work/sess/none")" "" "ticket without any key"

admin PUT plugin_metadata/ssl-session-ticket "{\"keys\": $(keys_json 1 2)}"
rev=$(revision)
wait_status 0 ok "$rev"
wait_status 1 ok "$rev"
cross_all 0 1 1
echo "passed: traditional nodes resume each other's sessions"

# the Admin API keeps the native keys of its shared session cache
admin_sess="$work/sess/admin"
expect_eq "$(handshake "$(admin_port 0)" 1.2 "$admin_sess")" New "Admin API session"
if [ -z "$(openssl sess_id -in "$admin_sess" -noout -text | grep 'TLS session ticket:')" ] \
   || [ -n "$(ticket_key "$admin_sess")" ]; then
    echo "failed: the Admin API does not issue its native tickets"
    exit 1
fi
expect_eq "$(handshake "$(admin_port 0)" 1.2 "$admin_sess.2" "$admin_sess")" Reused \
          "Admin API session"
expect_eq "$(handshake "$(https_port 1)" 1.2 "$admin_sess.3" "$admin_sess")" New \
          "Admin API session on the business listener of another node"
echo "passed: the Admin API keeps its native session tickets"

# reordered: the new first key issues, the others still decrypt
for port in $listeners; do
    handshake "$($port 0)" 1.2 "$work/sess/$port-key1" > /dev/null
    expect_eq "$(ticket_key "$work/sess/$port-key1")" ticket-name-0001 "$port key 1"
done
admin PUT plugin_metadata/ssl-session-ticket "{\"keys\": $(keys_json 2 1)}"
rev=$(revision)
wait_status 0 ok "$rev"
wait_status 1 ok "$rev"
cross_all 0 1 2
for port in $listeners; do
    # renewed with the first key, see t/plugin/ssl-session-ticket5.t
    expect_eq "$(handshake "$($port 1)" 1.2 "$work/sess/$port-renewed" \
                           "$work/sess/$port-key1")" Reused "$port: the older key on node 1"
done
echo "passed: reordered keys"

# removed: its sessions no longer resume on another node
admin PUT plugin_metadata/ssl-session-ticket "{\"keys\": $(keys_json 2)}"
rev=$(revision)
wait_status 0 ok "$rev"
wait_status 1 ok "$rev"
for port in $listeners; do
    for version in 1.2 1.3; do
        handshake "$($port 0)" "$version" "$work/sess/$port-$version-key2" > /dev/null
    done
    expect_eq "$(handshake "$($port 1)" 1.2 "$work/sess/x" "$work/sess/$port-key1")" New \
              "$port: a removed key on node 1"
done
echo "passed: removed keys"

# n -> 0: no stateless ticket, the earlier ones no longer resume elsewhere;
# the Admin API is not concerned
admin DELETE plugin_metadata/ssl-session-ticket
wait_status 0 off
wait_status 1 off
for port in $listeners; do
    for version in 1.2 1.3; do
        expect_eq "$(handshake "$($port 1)" "$version" "$work/sess/x" \
                               "$work/sess/$port-$version-key2")" New \
                  "$port $version: an earlier ticket without keys"
    done
    handshake "$($port 0)" 1.2 "$work/sess/off" > /dev/null
    expect_eq "$(ticket_key "$work/sess/off")" "" "$port: TLSv1.2 ticket without keys"
done
expect_eq "$(handshake "$(admin_port 0)" 1.2 "$work/sess/admin.4" "$admin_sess")" Reused \
          "Admin API session without business keys"
echo "passed: n -> 0"

# 0 -> n
admin PUT plugin_metadata/ssl-session-ticket "{\"keys\": $(keys_json 3)}"
rev=$(revision)
wait_status 0 ok "$rev"
wait_status 1 ok "$rev"
cross_all 0 1 3
echo "passed: 0 -> n"

# a restarted node, a reloaded one
stop_node 1
start_node 1
wait_status 1 ok "$rev"
cross_all 0 1 3 "https_port tls_port"
# the reloaded node publishes its target again, in a new configuration
# generation of the runtime
wait_status 0 ok "$rev"
version=$(echo "$status" | grep -o '"version":"[^"]*"' | cut -d '"' -f 4)
(cd "$(node_dir 0)" && ./bin/apisix reload)
wait_status 0 ok "$rev" "$version"
cross_all 0 1 3 "https_port tls_port"
echo "passed: restart and reload"

stop_node 1
make stop


# traditional nodes, the keys of the built-in generator

etcdctl del "$record_key" > /dev/null
write_conf 0 traditional generated
write_conf 1 traditional generated
start_node 0
start_node 1
wait_status 0 ok
wait_status 1 ok
rev=$(etcdctl get "$record_key" -w fields | grep '"ModRevision"' | grep -o '[0-9]*')
wait_status 0 ok "$rev"
wait_status 1 ok "$rev"
if ! echo "$status" | grep -q '"source":"generated"'; then
    echo "failed: the keys are not generated: $status"
    exit 1
fi
cross_all 0 1 any
echo "passed: generated keys on traditional nodes"

# n -> 0 -> n: disabled by the local policy, then enabled again with the
# same keys
for port in https_port tls_port; do
    handshake "$($port 0)" 1.2 "$work/sess/$port-generated" > /dev/null
done
for i in 0 1; do
    ENABLED=false write_conf $i traditional generated
    (cd "$(node_dir $i)" && ./bin/apisix reload)
done
wait_status 0 off
wait_status 1 off
if ! echo "$status" | grep -q '"reason":"disabled_by_policy"'; then
    echo "failed: the keys are not disabled by the policy: $status"
    exit 1
fi
for port in https_port tls_port; do
    expect_eq "$(handshake "$($port 1)" 1.2 "$work/sess/x" "$work/sess/$port-generated")" New \
              "$port: a generated ticket once disabled"
done
for i in 0 1; do
    write_conf $i traditional generated
    (cd "$(node_dir $i)" && ./bin/apisix reload)
done
wait_status 0 ok
wait_status 1 ok
for port in https_port tls_port; do
    expect_eq "$(handshake "$($port 1)" 1.2 "$work/sess/x" "$work/sess/$port-generated")" \
              Reused "$port: a generated ticket enabled again"
done
echo "passed: generated keys disabled and enabled again"

stop_node 1
make stop


# a control plane generates the keys, two data planes use them

etcdctl del "$record_key" > /dev/null
write_conf 0 control_plane generated
write_conf 1 data_plane generated
write_conf 2 data_plane generated
(cd "$(node_dir 0)" && ./bin/apisix start)
wait_for_tcp 127.0.0.1 "$(admin_port 0)" 20
start_node 1
start_node 2
wait_status 1 ok
wait_status 2 ok
rev=$(etcdctl get "$record_key" -w fields | grep '"ModRevision"' | grep -o '[0-9]*')
wait_status 1 ok "$rev"
wait_status 2 ok "$rev"
cross_all 1 2 any
echo "passed: generated keys of a control plane on data planes"

stop_node 1
stop_node 2
make stop


# standalone nodes, the same keys in their configuration

for i in 1 2; do
    write_conf $i standalone external
    {
        echo "ssls:"
        echo "  - id: 1"
        echo "    snis: [test.com]"
        echo "    cert: |"
        sed 's/^/      /' t/certs/apisix.crt
        echo "    key: |"
        sed 's/^/      /' t/certs/apisix.key
        echo "stream_routes:"
        echo "  - id: 1"
        echo "    upstream:"
        echo "      nodes:"
        echo "        \"127.0.0.1:2379\": 1"
        echo "      type: roundrobin"
        echo "plugin_metadata:"
        echo "  - id: ssl-session-ticket"
        echo "    keys: $(keys_json 4 5)"
        echo "#END"
    } > "$(node_dir $i)/conf/apisix.yaml"
    start_node $i
done
wait_status 1 ok
wait_status 2 ok
cross_all 1 2 4
echo "passed: standalone nodes"

stop_node 1
stop_node 2


# Stream only, then HTTP only: each subsystem initializes and converges alone

etcdctl del "$record_key" > /dev/null
write_conf 1 traditional external stream
write_conf 2 traditional external stream
start_node 1
start_node 2
wait_status 1 off
etcdctl put "$record_key" "{\"id\":\"ssl-session-ticket\",\"keys\":$(keys_json 6),\
\"origin\":{\"source\":\"external\",\"disabled\":false}}" > /dev/null
wait_status 1 ok
wait_status 2 ok
cross_all 1 2 6 "tls_port mixed_port"
stop_node 1
stop_node 2
echo "passed: Stream only"

write_conf 0 traditional external http
write_conf 1 traditional external http
start_node 0
start_node 1
admin_url="http://127.0.0.1:$(admin_port 0)"
admin PUT plugin_metadata/ssl-session-ticket "{\"keys\": $(keys_json 7)}"
rev=$(revision)
wait_status 0 ok "$rev"
wait_status 1 ok "$rev"
cross_all 0 1 7 "https_port"
echo "passed: HTTP only"

stop_node 1
make stop
etcdctl del "$record_key" > /dev/null

echo "passed: TLS sessions resume across the nodes that share the keys"
