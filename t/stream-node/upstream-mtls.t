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
use t::APISIX;

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("stream_enable", 1);

        # An mTLS-enabled upstream: it requires (and verifies) a client
        # certificate signed by mtls_ca. A connection without a valid client
        # certificate is rejected during the TLS handshake.
        my $stream_config = $block->stream_config // '';
        $stream_config .= <<_EOC_;
        server {
            listen 8765 ssl;
            ssl_certificate             ../../certs/mtls_server.crt;
            ssl_certificate_key         ../../certs/mtls_server.key;
            ssl_client_certificate      ../../certs/mtls_ca.crt;
            ssl_verify_client           on;

            content_by_lua_block {
                local sock = ngx.req.socket()
                local data = sock:receive("1")
                ngx.say("hello mtls upstream")
            }
        }
_EOC_

        $block->set_value("extra_stream_config", $stream_config);
    }
});

run_tests();

__DATA__

=== TEST 1: set upstream (with client cert) & stream_route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                scheme = "tls",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:8765"] = 1,
                },
                tls = {
                    client_cert = ssl_cert,
                    client_key = ssl_key,
                }
            }
            local code, body = t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t.test('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream_id": "1"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: hit route, upstream mTLS succeeds with client cert
--- stream_request
mmm
--- stream_response
hello mtls upstream
--- no_error_log
[error]



=== TEST 3: set upstream WITHOUT client cert
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local code, body = t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "scheme": "tls",
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:8765": 1
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: hit route, upstream rejects connection without client cert
--- stream_request
mmm
--- stream_response eval
qr//
--- error_log
client sent no required SSL certificate while SSL handshaking



=== TEST 5: set upstream client cert via client_cert_id (ssl object)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")

            local data = {
                cert = ssl_cert,
                key = ssl_key,
                type = "client",
            }
            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "scheme": "tls",
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:8765": 1
                    },
                    "tls": {
                        "client_cert_id": "1"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: hit route, upstream mTLS succeeds with client_cert_id
--- stream_request
mmm
--- stream_response
hello mtls upstream
--- no_error_log
[error]
