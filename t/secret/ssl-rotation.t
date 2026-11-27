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

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    # A mock vault holding a cert and its key at kv/apisix/pair. Unless a version
    # is pinned, every read returns the next version of the pair, so any two
    # reads straddle a rotation.
    my $http_config = $block->http_config // <<_EOC_;
    lua_shared_dict mock_vault 1m;

    server {
        listen 18200;

        location /v1/kv/apisix/pair {
            content_by_lua_block {
                local dict = ngx.shared.mock_vault
                local version = dict:get("pinned") or dict:incr("reads", 1, 0)
                local name = version % 2 == 0 and "mtls_client" or "mtls_server"
                local t = require("lib.test_admin")
                ngx.say(require("toolkit.json").encode({data = {
                    cert = t.read_file("t/certs/" .. name .. ".crt"),
                    key = t.read_file("t/certs/" .. name .. ".key"),
                }}))
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!defined $block->upstream_server_config) {
        $block->set_value("upstream_server_config", <<_EOC_);
    ssl_client_certificate ../../certs/mtls_ca.crt;
    ssl_verify_client on;

    location /client_dn {
        return 200;
    }
_EOC_
    }
});

run_tests;

__DATA__

=== TEST 1: ssl objects whose cert and key are refs into the same vault entry
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/vault/pair',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:18200",
                    "prefix": "kv/apisix",
                    "token": "root"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                [[{
                    "cert": "$secret://vault/pair/pair/cert",
                    "key": "$secret://vault/pair/pair/key",
                    "sni": "test.com"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/ssls/2',
                ngx.HTTP_PUT,
                [[{
                    "type": "client",
                    "cert": "$secret://vault/pair/pair/cert",
                    "key": "$secret://vault/pair/pair/key"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/client_dn",
                    "upstream": {
                        "scheme": "https",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1983": 1
                        },
                        "tls": {
                            "client_cert_id": 2
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: handshakes keep a matching pair while the secret rotates on every read
--- yaml_config
apisix:
  lru:
    secret:
      ttl: 1
--- config
    listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

    location /t {
        content_by_lua_block {
            -- wait for the secret config to sync
            ngx.sleep(0.5)

            local failed = 0
            local deadline = ngx.now() + 3.5
            while ngx.now() < deadline do
                local sock = ngx.socket.tcp()
                sock:settimeout(2000)
                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    return ngx.say("failed to connect: ", err)
                end

                if not sock:sslhandshake(nil, "test.com", false) then
                    failed = failed + 1
                end
                sock:close()
                ngx.sleep(0.1)
            end

            ngx.say("failed handshakes: ", failed)
            ngx.say("rotated: ", ngx.shared.mock_vault:get("reads") >= 2)
        }
    }
--- response_body
failed handshakes: 0
rotated: true
--- error_log
successfully refresh stale obj for key



=== TEST 3: a cert fetched after its key was cached alone still gets a matching key
--- config
    listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

    location /t {
        content_by_lua_block {
            -- wait for the secret config to sync
            ngx.sleep(0.5)

            local dict = ngx.shared.mock_vault
            dict:set("pinned", 0)
            require("apisix.secret").fetch_secrets({key = "$secret://vault/pair/pair/key"}, true)

            -- rotate, and outlive the short-lived copy of the vault entry
            dict:set("pinned", 1)
            ngx.sleep(1.5)

            local sock = ngx.socket.tcp()
            sock:settimeout(2000)
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                return ngx.say("failed to connect: ", err)
            end

            local sess, err = sock:sslhandshake(nil, "test.com", false)
            if not sess then
                return ngx.say("failed to do SSL handshake: ", err)
            end
            ngx.say("ssl handshake: true")
        }
    }
--- response_body
ssl handshake: true



=== TEST 4: upstream client certs keep a matching pair while the secret rotates on every read
--- yaml_config
apisix:
  lru:
    secret:
      ttl: 1
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            -- wait for the secret config to sync
            ngx.sleep(0.5)

            local failed = 0
            local deadline = ngx.now() + 3.5
            while ngx.now() < deadline do
                local res = http.new():request_uri("http://127.0.0.1:" .. ngx.var.server_port
                                                   .. "/client_dn")
                if not (res and res.status == 200) then
                    failed = failed + 1
                end
                ngx.sleep(0.1)
            end

            ngx.say("failed requests: ", failed)
            ngx.say("rotated: ", ngx.shared.mock_vault:get("reads") >= 2)
        }
    }
--- response_body
failed requests: 0
rotated: true
--- error_log
successfully refresh stale obj for key



=== TEST 5: callers sharing a container read are released when the read fails or its caller goes away
--- config
    location /t {
        content_by_lua_block {
            local cache = require("apisix.secret").new_container_cache()
            local reads = 0
            local function failing_read()
                reads = reads + 1
                ngx.sleep(0.2)
                error("boom")
            end
            local function slow_read()
                reads = reads + 1
                ngx.sleep(0.2)
                return "value" .. reads
            end

            local start = ngx.now()
            local threads = {}
            for i = 1, 3 do
                threads[i] = ngx.thread.spawn(cache, "failing", "v", 5, failing_read)
            end
            for i = 1, 3 do
                local _, val, err = ngx.thread.wait(threads[i])
                ngx.say("failing read: ", val, " ", err:find("boom", 1, true) ~= nil)
            end

            -- the first caller is killed while the read is in flight
            local first = ngx.thread.spawn(cache, "slow", "v", 5, slow_read)
            local second = ngx.thread.spawn(cache, "slow", "v", 5, slow_read)
            ngx.thread.kill(first)
            local _, val = ngx.thread.wait(second)
            ngx.say("after the first caller went away: ", val)

            ngx.update_time()
            ngx.say("reads: ", reads, ", waited less than a second: ", ngx.now() - start < 1)
        }
    }
--- response_body
failing read: nil true
failing read: nil true
failing read: nil true
after the first caller went away: value2
reads: 2, waited less than a second: true
