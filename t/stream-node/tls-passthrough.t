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
use t::APISIX 'no_plan';

log_level('info');
no_root_location();
worker_connections(1024);

# 1997 and 1998 terminate TLS themselves, so a client that completes a handshake
# with either of them proves the bytes were forwarded rather than answered. The
# two upstreams below are cross-mapped against the routes' own upstreams, so in
# the mixed tests only the target the preread phase picked can explain the answer.
my $stream_backends = <<'_EOC_';
    upstream apisix_test_terminate   { server 127.0.0.1:1997; }
    upstream apisix_test_passthrough { server 127.0.0.1:1998; }

    server {
        listen 1997 ssl;
        # not cert/apisix.crt: the gateway holds no copy of this one
        ssl_certificate     ../../certs/mtls_server.crt;
        ssl_certificate_key ../../certs/mtls_server.key;
        content_by_lua_block {
            ngx.say("hello from backend A")
        }
    }

    server {
        listen 1998 ssl;
        ssl_certificate     cert/apisix.crt;
        ssl_certificate_key cert/apisix.key;
        content_by_lua_block {
            ngx.say("hello from backend B")
        }
    }
_EOC_

# A passthrough listen: no `ssl`, so it holds no certificate and could not
# terminate anything even if it wanted to.
my $passthrough_server = <<'_EOC_';
    listen 2005;
    ssl_preread on;

    preread_by_lua_block {
        ngx.sleep(0.1)
        apisix.stream_preread_phase(true)
    }

    proxy_pass apisix_backend;
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    return unless defined $block->stream_tls_request;

    if (!defined $block->extra_stream_config) {
        $block->set_value("extra_stream_config", $stream_backends);
    }

    if (!defined $block->stream_server_config) {
        $block->set_value("stream_server_config", $passthrough_server);
    }
});

run_tests();

__DATA__

=== TEST 1: set two stream routes, matched by SNI
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local code, body = t.test('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "sni": "admin.apisix.dev",
                    "upstream": {
                        "nodes": {"127.0.0.1:1997": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t.test('/apisix/admin/stream_routes/2',
                ngx.HTTP_PUT,
                [[{
                    "sni": "b.test.com",
                    "upstream": {
                        "nodes": {"127.0.0.1:1998": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: the prereaded SNI selects the upstream, which terminates the handshake
--- custom_trusted_cert: ../../certs/mtls_ca.crt
--- stream_tls_request
mmm
--- stream_sni: admin.apisix.dev
--- stream_tls_verify
--- response_body
hello from backend A
--- error_log
proxy request to 127.0.0.1:1997



=== TEST 3: a second SNI on the same port picks the other upstream
--- stream_tls_request
mmm
--- stream_sni: b.test.com
--- response_body
hello from backend B
--- error_log
proxy request to 127.0.0.1:1998



=== TEST 4: a ClientHello with no SNI falls back instead of matching on ""
--- yaml_config
apisix:
  node_listen: 1984
  ssl:
    fallback_sni: b.test.com
--- stream_tls_request
mmm
--- response_body
hello from backend B
--- error_log
proxy request to 127.0.0.1:1998



=== TEST 5: set a passthrough route and a terminating route for the mixed listen
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local code, body = t.test('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "sni": "admin.apisix.dev",
                    "tls_passthrough": true,
                    "upstream": {
                        "nodes": {"127.0.0.1:1997": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t.test('/apisix/admin/stream_routes/2',
                ngx.HTTP_PUT,
                [[{
                    "sni": "b.test.com",
                    "upstream": {
                        "nodes": {"127.0.0.1:1998": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: a route asking for passthrough goes to the passthrough target
--- stream_server_config
    listen 2005;
    ssl_preread on;

    set $stream_tls_target "";

    preread_by_lua_block {
        ngx.sleep(0.1)
        apisix.stream_tls_route_phase("apisix_test_terminate",
                                      "apisix_test_passthrough")
    }

    proxy_pass $stream_tls_target;
--- stream_tls_request
mmm
--- stream_sni: admin.apisix.dev
--- response_body
hello from backend B
--- error_log
target: apisix_test_passthrough



=== TEST 7: a route that did not ask for it goes to the terminating target
--- stream_server_config
    listen 2005;
    ssl_preread on;

    set $stream_tls_target "";

    preread_by_lua_block {
        ngx.sleep(0.1)
        apisix.stream_tls_route_phase("apisix_test_terminate",
                                      "apisix_test_passthrough")
    }

    proxy_pass $stream_tls_target;
--- stream_tls_request
mmm
--- stream_sni: b.test.com
--- response_body
hello from backend A
--- error_log
target: apisix_test_terminate



=== TEST 8: set a route with a tls upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local code, body = t.test('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "sni": "admin.apisix.dev",
                    "upstream": {
                        "scheme": "tls",
                        "nodes": {"127.0.0.1:1997": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 9: a tls upstream on a passthrough listen is refused
--- stream_tls_request
mmm
--- stream_sni: admin.apisix.dev
--- response_body_like eval
qr/failed to (do SSL handshake|receive)/
--- error_log
upstream scheme `tls` can not be used on a tls_passthrough listen
