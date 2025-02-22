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
});

run_tests();

__DATA__

=== TEST 1: Create route (jwt local, audience required)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "apisix",
                                "client_secret": "secret",
                                "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                                "bearer_only": true,
                                "claim_validator": {
                                    "audience": {
                                        "required": true
                                    }
                                },
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvxeMCu3jE1QChgzCwlxP\n]] ..
                                    [[mOkRHQORlOvwGpCX9zRCkMAq7a6jvlQTyM+OOfnnX9xBF4YxRRj3VOqdBJBdEjC2\n]] ..
                                    [[jLFQUECdqnD+hZaCGIsk91grP4G7XaFqud7nAH1rniMh1rKLy3NFYTl5tK4U2IPP\n]] ..
                                    [[JzIye8ur2JHyzE+qpcAEp/U6M4I2rdPX1gE2ze8gYuIr1VbCg6Nkt45DslZ2GDI8\n]] ..
                                    [[2TtwkpMlEjJfmbEnrLHkigPXNs6IHyiFPN95462gPG5TBX3YpxDCP/cnHhMeeyFI\n]] ..
                                    [[56WNYlhy0iLYmRfiyhKXi76fYKa/PIIUfOSErrKgKsHJp7HQKo48O4Gz5tQyL1IF\n]] ..
                                    [[QQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 2: Access route with a valid token (with audience)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:8080/realms/basic/protocol/openid-connect/token", {
                method = "POST",
                body = "client_id=apisix&client_secret=secret&grant_type=password&username=jack&password=jack",
                headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            local access_token = require("toolkit.json").decode(res.body).access_token
            local res, err = httpc:request_uri("http://127.0.0.1:1980/hello", {
                method = "GET",
                headers = { Authorization = "Bearer " .. access_token }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            ngx.status = res.status
        }
    }



=== TEST 3: Update route (jwt local, audience required, custom claim)
Use a custom non-existent claim to simulate the case where the standard field "aud" is not included.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "apisix",
                                "client_secret": "secret",
                                "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                                "bearer_only": true,
                                "claim_validator": {
                                    "audience": {
                                        "claim": "custom_claim",
                                        "required": true
                                    }
                                },
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvxeMCu3jE1QChgzCwlxP\n]] ..
                                    [[mOkRHQORlOvwGpCX9zRCkMAq7a6jvlQTyM+OOfnnX9xBF4YxRRj3VOqdBJBdEjC2\n]] ..
                                    [[jLFQUECdqnD+hZaCGIsk91grP4G7XaFqud7nAH1rniMh1rKLy3NFYTl5tK4U2IPP\n]] ..
                                    [[JzIye8ur2JHyzE+qpcAEp/U6M4I2rdPX1gE2ze8gYuIr1VbCg6Nkt45DslZ2GDI8\n]] ..
                                    [[2TtwkpMlEjJfmbEnrLHkigPXNs6IHyiFPN95462gPG5TBX3YpxDCP/cnHhMeeyFI\n]] ..
                                    [[56WNYlhy0iLYmRfiyhKXi76fYKa/PIIUfOSErrKgKsHJp7HQKo48O4Gz5tQyL1IF\n]] ..
                                    [[QQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 4: Access route with an invalid token (without audience)
Use a custom non-existent claim to simulate the case where the standard field "aud" is not included.
Note the assertion in the error log, where it is shown that the custom claim field name did take effect.
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:8080/realms/basic/protocol/openid-connect/token", {
                method = "POST",
                body = "client_id=apisix&client_secret=secret&grant_type=password&username=jack&password=jack",
                headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            local access_token = require("toolkit.json").decode(res.body).access_token
            res, err = httpc:request_uri("http://127.0.0.1:"..ngx.var.server_port.."/hello", {
                method = "GET",
                headers = { Authorization = "Bearer " .. access_token }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- error_code: 403
--- response_body
{"error":"required audience claim not present"}
--- error_log
OIDC introspection failed: required audience (custom_claim) not present


=== TEST 5: Update route (jwt local, audience required, custom claim)
Use "iss" to fake "aud".
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "apisix",
                                "client_secret": "secret",
                                "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                                "bearer_only": true,
                                "claim_validator": {
                                    "audience": {
                                        "claim": "iss",
                                        "required": true
                                    }
                                },
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvxeMCu3jE1QChgzCwlxP\n]] ..
                                    [[mOkRHQORlOvwGpCX9zRCkMAq7a6jvlQTyM+OOfnnX9xBF4YxRRj3VOqdBJBdEjC2\n]] ..
                                    [[jLFQUECdqnD+hZaCGIsk91grP4G7XaFqud7nAH1rniMh1rKLy3NFYTl5tK4U2IPP\n]] ..
                                    [[JzIye8ur2JHyzE+qpcAEp/U6M4I2rdPX1gE2ze8gYuIr1VbCg6Nkt45DslZ2GDI8\n]] ..
                                    [[2TtwkpMlEjJfmbEnrLHkigPXNs6IHyiFPN95462gPG5TBX3YpxDCP/cnHhMeeyFI\n]] ..
                                    [[56WNYlhy0iLYmRfiyhKXi76fYKa/PIIUfOSErrKgKsHJp7HQKo48O4Gz5tQyL1IF\n]] ..
                                    [[QQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 6: Access route with an valid token (with custom audience claim)
Use "iss" to fake "aud".
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:8080/realms/basic/protocol/openid-connect/token", {
                method = "POST",
                body = "client_id=apisix&client_secret=secret&grant_type=password&username=jack&password=jack",
                headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            local access_token = require("toolkit.json").decode(res.body).access_token
            res, err = httpc:request_uri("http://127.0.0.1:"..ngx.var.server_port.."/hello", {
                method = "GET",
                headers = { Authorization = "Bearer " .. access_token }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            ngx.status = res.status
            ngx.say(res.body)
        }
    }



=== TEST 7: Update route (jwt local, audience required, match client_id)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "apisix",
                                "client_secret": "secret",
                                "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                                "bearer_only": true,
                                "claim_validator": {
                                    "audience": {
                                        "required": true,
                                        "match_with_client_id": true
                                    }
                                },
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvxeMCu3jE1QChgzCwlxP\n]] ..
                                    [[mOkRHQORlOvwGpCX9zRCkMAq7a6jvlQTyM+OOfnnX9xBF4YxRRj3VOqdBJBdEjC2\n]] ..
                                    [[jLFQUECdqnD+hZaCGIsk91grP4G7XaFqud7nAH1rniMh1rKLy3NFYTl5tK4U2IPP\n]] ..
                                    [[JzIye8ur2JHyzE+qpcAEp/U6M4I2rdPX1gE2ze8gYuIr1VbCg6Nkt45DslZ2GDI8\n]] ..
                                    [[2TtwkpMlEjJfmbEnrLHkigPXNs6IHyiFPN95462gPG5TBX3YpxDCP/cnHhMeeyFI\n]] ..
                                    [[56WNYlhy0iLYmRfiyhKXi76fYKa/PIIUfOSErrKgKsHJp7HQKo48O4Gz5tQyL1IF\n]] ..
                                    [[QQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 8: Access route with an valid token (with client id as audience)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:8080/realms/basic/protocol/openid-connect/token", {
                method = "POST",
                body = "client_id=apisix&client_secret=secret&grant_type=password&username=jack&password=jack",
                headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            local access_token = require("toolkit.json").decode(res.body).access_token
            res, err = httpc:request_uri("http://127.0.0.1:"..ngx.var.server_port.."/hello", {
                method = "GET",
                headers = { Authorization = "Bearer " .. access_token }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            ngx.status = res.status
            ngx.say(res.body)
        }
    }



=== TEST 9: Update route (jwt local, audience required, match client_id)
Use the apisix-no-aud client. According to Keycloak's default implementation, when unconfigured,
only the account is listed as an audience, not the client id.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "apisix-no-aud",
                                "client_secret": "secret",
                                "discovery": "http://127.0.0.1:8080/realms/basic/.well-known/openid-configuration",
                                "bearer_only": true,
                                "claim_validator": {
                                    "audience": {
                                        "required": true,
                                        "match_with_client_id": true
                                    }
                                },
                                "public_key": "-----BEGIN PUBLIC KEY-----\n]] ..
                                    [[MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvxeMCu3jE1QChgzCwlxP\n]] ..
                                    [[mOkRHQORlOvwGpCX9zRCkMAq7a6jvlQTyM+OOfnnX9xBF4YxRRj3VOqdBJBdEjC2\n]] ..
                                    [[jLFQUECdqnD+hZaCGIsk91grP4G7XaFqud7nAH1rniMh1rKLy3NFYTl5tK4U2IPP\n]] ..
                                    [[JzIye8ur2JHyzE+qpcAEp/U6M4I2rdPX1gE2ze8gYuIr1VbCg6Nkt45DslZ2GDI8\n]] ..
                                    [[2TtwkpMlEjJfmbEnrLHkigPXNs6IHyiFPN95462gPG5TBX3YpxDCP/cnHhMeeyFI\n]] ..
                                    [[56WNYlhy0iLYmRfiyhKXi76fYKa/PIIUfOSErrKgKsHJp7HQKo48O4Gz5tQyL1IF\n]] ..
                                    [[QQIDAQAB\n]] ..
                                    [[-----END PUBLIC KEY-----",
                                "token_signing_alg_values_expected": "RS256"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 10: Access route with an invalid token (without client id as audience)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:8080/realms/basic/protocol/openid-connect/token", {
                method = "POST",
                body = "client_id=apisix-no-aud&client_secret=secret&grant_type=password&username=jack&password=jack",
                headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            local access_token = require("toolkit.json").decode(res.body).access_token
            res, err = httpc:request_uri("http://127.0.0.1:"..ngx.var.server_port.."/hello", {
                method = "GET",
                headers = { Authorization = "Bearer " .. access_token }
            })
            if not res then
                ngx.say("FAILED: ", err)
                return
            end
            ngx.status = res.status
            ngx.say(res.body)
        }
    }
--- error_code: 403
--- response_body
{"error":"mismatched audience"}
--- error_log
OIDC introspection failed: audience does not match the client id
