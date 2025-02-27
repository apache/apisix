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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
# no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
		my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 8089;

        location /realms/University/.well-known/openid-configuration {
            content_by_lua_block {
                ngx.say("{
  "issuer": "https://securetoken.google.com/test-firebase-project",
  "jwks_uri": "https://www.googleapis.com/service_accounts/v1/jwk/securetoken\@system.gserviceaccount.com",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [
    "public"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ]
}")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: Check configuration of cookie
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {
                    client_id = "course_management",
                    client_secret = "tbsmDOpsHwdgIqYl2NltGRTKzjIzvEmT",
                    discovery = "http://127.0.0.1:8089/realms/University/.well-known/openid-configuration",
                    session = {
                        secret = "6S8IO+Pydgb33LIor8T9ClER0T/sglFAjClFeAF3RsY=",
                        cookie = {
                            lifetime = 86400
                        }
                    }
                },
            }
            local plugin = require("apisix.plugins.openid-connect")
            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done



=== TEST 2: Set up new route with wrong valid_issuers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "dummy",
                                "client_secret": "dummy",
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "ssl_verify": true,
                                "timeout": 10,
                                "bearer_only": true,
                                "use_jwks": true,
																"valid_issuers": 123
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body eval
qr/\{"error_msg":"failed to check the configuration of plugin openid-connect err: property \\"valid_issuers\\" validation failed.*"\}/



=== TEST 3: Set up new route with valid valid_issuers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "dummy",
                                "client_secret": "dummy",
                                "discovery": "http://127.0.0.1:8080/realms/University/.well-known/openid-configuration",
                                "ssl_verify": true,
                                "timeout": 10,
                                "bearer_only": true,
                                "use_jwks": true,
																"valid_issuers": ["https://securetoken.google.com/test-firebase-project"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
