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
BEGIN {
    $ENV{VAULT_TOKEN} = "root";
    $ENV{LAKERA_API_KEY} = "lakera-secret-env";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    # Mock the Lakera Guard /v2/guard endpoint. It only returns a clean verdict
    # when the api_key was actually resolved -- i.e. the Bearer token carries the
    # secret value, not a "$secret://"/"$env://" reference. A resolved key (both
    # the vault- and env-managed ones share the "lakera-secret" marker) therefore
    # yields an end-to-end 200; an unresolved one is rejected with 401.
    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 6724;

            default_type 'application/json';

            location /v2/guard {
                content_by_lua_block {
                    local core = require("apisix.core")
                    local fixture_loader = require("lib.fixture_loader")
                    ngx.req.read_body()
                    local auth = ngx.req.get_headers()["Authorization"] or ""

                    if not core.string.find(auth, "lakera-secret") then
                        ngx.status = 401
                        ngx.say([[{"error":"api key was not resolved"}]])
                        return
                    end

                    local content = fixture_loader.load("lakera/scan-clean.json")
                    ngx.status = 200
                    ngx.print(content)
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: store the Lakera api_key into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/lakera api_key=lakera-secret-vault
--- response_body
Success! Data written to: kv/apisix/lakera



=== TEST 2: set api_key as a reference to a vault secret
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- register the vault secret backend
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix" : "kv/apisix",
                    "token" : "root"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai-compatible",
                          "auth": { "header": { "Authorization": "Bearer token" } },
                          "options": { "model": "gpt-4" },
                          "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" },
                          "ssl_verify": false
                      },
                      "ai-lakera-guard": {
                          "api_key": "$secret://vault/test1/lakera/api_key",
                          "lakera_endpoint": "http://127.0.0.1:6724/v2/guard"
                      }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 3: vault-managed api_key resolves and the request passes
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body_like eval
qr/1 \+ 1 = 2/



=== TEST 4: set api_key as a reference to an environment variable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                      "ai-proxy": {
                          "provider": "openai-compatible",
                          "auth": { "header": { "Authorization": "Bearer token" } },
                          "options": { "model": "gpt-4" },
                          "override": { "endpoint": "http://127.0.0.1:1980/v1/chat/completions" },
                          "ssl_verify": false
                      },
                      "ai-lakera-guard": {
                          "api_key": "$env://LAKERA_API_KEY",
                          "lakera_endpoint": "http://127.0.0.1:6724/v2/guard"
                      }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("success")
        }
    }
--- response_body
success



=== TEST 5: env-managed api_key resolves and the request passes
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?" } ] }
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- error_code: 200
--- response_body_like eval
qr/1 \+ 1 = 2/
