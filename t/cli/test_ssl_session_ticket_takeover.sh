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

# Which listeners take over their session ticket keys, and what
# apisix.ssl.ssl_session_tickets means for the business listeners and for the
# Admin API, with and without a runtime that takes over the keys.

. ./t/cli/common.sh

exit_if_not_customed_nginx

# the server blocks of conf/nginx.conf that contain a line matching $1
server_block() {
    awk -v pat="$1" '
        function count(s, c) { return gsub(c, "", s) }
        !inside && /^[ \t]*server[ \t]*[{]/ { inside = 1; depth = 0; buf = "" }
        inside {
            buf = buf $0 "\n"
            depth += count($0, "[{]") - count($0, "[}]")
            if (depth == 0) {
                if (buf ~ pat) {
                    printf "%s", buf
                }
                inside = 0
            }
        }
    ' conf/nginx.conf
}

# expect <listen pattern> <tickets: on, off or none> <takeover: 0 or 1>
expect() {
    local block
    block=$(server_block "$1")
    if [ -z "$block" ]; then
        echo "failed: no server listens on $1"
        exit 1
    fi

    local on off marker
    on=$(echo "$block" | grep -c "ssl_session_tickets on;" || true)
    off=$(echo "$block" | grep -c "ssl_session_tickets off;" || true)
    marker=$(echo "$block" | grep -c "apisix_ssl_session_ticket_takeover on;" || true)
    case "$2" in
        on) [ "$on" = 1 ] && [ "$off" = 0 ] || { echo "failed: $1 tickets not on"; exit 1; } ;;
        off) [ "$on" = 0 ] && [ "$off" = 1 ] || { echo "failed: $1 tickets not off"; exit 1; } ;;
        none) [ "$on" = 0 ] && [ "$off" = 0 ] || { echo "failed: $1 sets tickets"; exit 1; } ;;
    esac
    if [ "$marker" != "$3" ]; then
        echo "failed: $1 takeover is $marker, not $3"
        exit 1
    fi
}

# write conf/config.yaml with every kind of listener, and the given
# ssl_session_tickets value (or none)
write_conf() {
    local ssl=""
    if [ -n "$1" ]; then
        ssl="ssl:
        ssl_session_tickets: $1"
    fi

    echo "
apisix:
    proxy_mode: http&stream
    stream_proxy:
        tcp:
            - addr: 9100
              tls: true
            - addr: 9101
              tls_passthrough: true
            - addr: 9102
              tls: true
              tls_passthrough: true
            - 9103
    $ssl
deployment:
    admin:
        https_admin: true
        admin_api_mtls:
            admin_ssl_cert: '../t/certs/apisix_admin_ssl.crt'
            admin_ssl_cert_key: '../t/certs/apisix_admin_ssl.key'
plugin_attr:
    prometheus:
        export_addr:
            ip: 127.0.0.1
            port: 9091
" > conf/config.yaml
}

check() {
    local tickets="$1" admin="$2" business="$3" stream="$4" takeover="$5"

    write_conf "$tickets"
    make init

    expect "listen 0[.]0[.]0[.]0:9180 +ssl" "$admin" 0
    expect "listen 0[.]0[.]0[.]0:9443 +ssl +default_server" "$business" "$takeover"
    # Stream: direct TLS, the internal server that terminates a mixed listen
    expect "listen 9100 +ssl" "$stream" "$takeover"
    expect "listen unix:[^ ]*stls-t[0-9]*[.]sock +ssl" "$stream" "$takeover"
    # never: TLS passthrough and its mixed front, plain TCP, the Control API,
    # the Prometheus export
    expect "listen 9101[ ;]" none 0
    expect "listen 9102[ ;]" none 0
    expect "listen 127[.]0[.]0[.]1:9090[ ;]" none 0
    expect "listen 127[.]0[.]0[.]1:9091[ ;]" none 0

    local markers
    markers=$(grep -c "apisix_ssl_session_ticket_takeover on;" conf/nginx.conf || true)
    if [ "$markers" != $(( takeover * 3 )) ]; then
        echo "failed: $markers listeners take over the keys"
        exit 1
    fi
}

if ssl_session_ticket_takeover; then
    # the business listeners always issue tickets with the shared keys only,
    # the Admin API keeps its native ones when explicitly asked to
    check "" off off off 1
    check true on off off 1
    check false off off off 1
    echo "passed: the business TLS listeners take over their session ticket keys"
else
    # as before: native tickets on the business HTTPS listener and the Admin
    # API when explicitly asked, Stream TLS at the native default
    check "" off off none 0
    check true on on none 0
    check false off off none 0
    echo "passed: without the takeover, the session tickets are native"
fi
