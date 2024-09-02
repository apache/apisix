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
    $ENV{SECRET_ACCESS_KEY} = "super-secret";
    $ENV{ACCESS_KEY_ID} = "access-key-id";
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

    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 2668;

            default_type 'application/json';

            location / {
                content_by_lua_block {
                    local json = require("cjson.safe")
                    local core = require("apisix.core")
                    local open = io.open

                    local f = open('t/assets/content-moderation-responses.json', "r")
                    local resp = f:read("*a")
                    f:close()

                    if not resp then
                        ngx.status(503)
                        ngx.say("[INTERNAL FAILURE]: failed to open response.json file")
                    end

                    local responses = json.decode(resp)
                    if not responses then
                        ngx.status(503)
                        ngx.say("[INTERNAL FAILURE]: failed to decode response.json contents")
                    end

                    local headers = ngx.req.get_headers()
                    local auth_header = headers["Authorization"]
                    if core.string.find(auth_header, "access-key-id") then
                        ngx.say(json.encode(responses["good_request"]))
                        return
                    end
                    ngx.status = 403
                    ngx.say("unauthorized")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/foo secret_access_key=super-secret
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/foo access_key_id=access-key-id
--- response_body
Success! Data written to: kv/apisix/foo
Success! Data written to: kv/apisix/foo



=== TEST 2: set secret_access_key and access_key_id as a reference to secret
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- put secret vault config
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
                    "uri": "/echo",
                    "plugins": {
                        "ai-content-moderation": {
                            "provider": {
                                "aws_comprehend": {
                                    "access_key_id": "$secret://vault/test1/foo/access_key_id",
                                    "secret_access_key": "$secret://vault/test1/foo/secret_access_key",
                                    "region": "us-east-1",
                                    "endpoint": "http://localhost:2668"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
success



=== TEST 3: good request should pass
--- request
POST /echo
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"good_request"}]}
--- error_code: 200
--- response_body chomp
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"good_request"}]}



=== TEST 4: set secret_access_key as a reference to env variable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-content-moderation": {
                            "provider": {
                                "aws_comprehend": {
                                    "access_key_id": "$env://ACCESS_KEY_ID",
                                    "secret_access_key": "$env://SECRET_ACCESS_KEY",
                                    "region": "us-east-1",
                                    "endpoint": "http://localhost:2668"
                                }
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say("success")
        }
    }
--- request
GET /t
--- response_body
success



=== TEST 5: good request should pass
--- request
POST /echo
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"good_request"}]}
--- error_code: 200
--- response_body chomp
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"good_request"}]}
