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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;
});

BEGIN {
    use t::APISIX;

    $ENV{APISIX_STREAM_ENV_CERT} = t::APISIX::read_file("t/certs/apisix.crt");
    $ENV{APISIX_STREAM_ENV_KEY}  = t::APISIX::read_file("t/certs/apisix.key");
}


run_tests();

__DATA__

=== TEST 1: set stream / ssl
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {
                cert = ssl_cert, key = ssl_key,
                sni = "test.com",
            }
            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t.test('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
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



=== TEST 2: hit route
--- stream_tls_request
mmm
--- stream_sni: test.com
--- response_body
hello world



=== TEST 3: wrong sni
--- stream_tls_request
mmm
--- stream_sni: xx.com
--- error_log
failed to match any SSL certificate by SNI: xx.com



=== TEST 4: missing sni
--- stream_tls_request
mmm
--- error_log
failed to find SNI



=== TEST 5: ensure table is reused in TLS handshake
--- stream_extra_init_by_lua
    local tablepool = require("apisix.core").tablepool
    local old_fetch = tablepool.fetch
    tablepool.fetch = function(name, ...)
        ngx.log(ngx.WARN, "fetch table ", name)
        return old_fetch(name, ...)
    end

    local old_release = tablepool.release
    tablepool.release = function(name, ...)
        ngx.log(ngx.WARN, "release table ", name)
        return old_release(name, ...)
    end
--- stream_tls_request
mmm
--- stream_sni: test.com
--- response_body
hello world
--- grep_error_log eval
qr/(fetch|release) table \w+/
--- grep_error_log_out
fetch table api_ctx
release table api_ctx
fetch table api_ctx
fetch table ctx_var
fetch table plugins
release table ctx_var
release table plugins
release table api_ctx

=== TEST 6: stream tls supports $ENV certificate reference
--- config
    location /t-env {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                cert = "$ENV://APISIX_STREAM_ENV_CERT",
                key  = "$ENV://APISIX_STREAM_ENV_KEY",
                sni  = "env.test.com",
            }

            local code, body = t.test('/apisix/admin/ssls/2',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t.test('/apisix/admin/stream_routes/2',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.say("passed")
        }
    }
--- request
GET /t-env
--- response_body
passed



=== TEST 7: hit stream route with env cert
--- stream_tls_request
hello
--- stream_sni: env.test.com
--- response_body
hello world

=== TEST 8: store cert and key in vault for stream tls
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/ssl \
    test.com.crt=@t/certs/apisix.crt \
    test.com.key=@t/certs/apisix.key
--- response_body
Success!


=== TEST 9: set secret provider (vault) for stream tls
--- config
    location /t-secret {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/secrets/vault/stream-test',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://0.0.0.0:8200",
                    "prefix": "kv/apisix",
                    "token": "root"
                }]],
                [[{
                    "key": "/apisix/secrets/vault/stream-test",
                    "value": {
                        "uri": "http://0.0.0.0:8200",
                        "prefix": "kv/apisix",
                        "token": "root"
                    }
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t-secret
--- response_body
passed



=== TEST 10: stream tls supports $secret certificate reference
--- config
    location /t-secret {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                cert = "$secret://vault/stream-test/ssl/test.com.crt",
                key  = "$secret://vault/stream-test/ssl/test.com.key",
                sni  = "secret.test.com",
            }

            local code, body = t.test('/apisix/admin/ssls/3',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t.test('/apisix/admin/stream_routes/3',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.say("passed")
        }
    }
--- request
GET /t-secret
--- response_body
passed



=== TEST 11: hit stream route with secret cert
--- stream_tls_request
hello
--- stream_sni: secret.test.com
--- response_body
hello world

