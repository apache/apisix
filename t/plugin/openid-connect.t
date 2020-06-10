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
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_id = "a", client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: missing client_id
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "client_id" is required
done
--- no_error_log
[error]



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({client_id = 123, client_secret = "b", discovery = "c"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "client_id" validation failed: wrong type: expected string, got number
done
--- no_error_log
[error]



=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "scope": "apisix"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": "no",
                                    "timeout": 10000,
                                    "scope": "apisix"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 5: access
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            ngx.status = res.status
            local location = res.headers['Location']
            if string.find(location, 'https://samples.auth0.com/authorize') ~= -1 and
                string.find(location, 'scope=apisix') ~= -1 and
                string.find(location, 'client_id=kbyuFDidLLm280LIwVFiazOqjO3ty8KH') ~= -1 and
                string.find(location, 'response_type=code') ~= -1 and
                string.find(location, 'redirect_uri=https://iresty.com') ~= -1 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- timeout: 10s
--- response_body
true
--- error_code: 302
--- no_error_log
[error]



=== TEST 6: update plugin with bearer_only=true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": "no",
                                    "timeout": 10000,
                                    "bearer_only": true,
                                    "scope": "apisix"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 7: access
--- timeout: 10s
--- request
GET /hello
--- error_code: 401
--- response_headers_like
WWW-Authenticate: Bearer realm=apisix
--- no_error_log
[error]
--- SKIP



=== TEST 8: update plugin public key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openid-connect": {
                                "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                "redirect_uri": "https://iresty.com",
                                "ssl_verify": false,
                                "timeout": 10,
                                "bearer_only": true,
                                "scope": "apisix",
                                "public_key": "-----BEGIN PUBLIC KEY-----
MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ
hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==
-----END PUBLIC KEY-----",
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "openid-connect": {
                                    "client_id": "kbyuFDidLLm280LIwVFiazOqjO3ty8KH",
                                    "client_secret": "60Op4HFM0I8ajz0WdiStAbziZ-VFQttXuxixHHs2R7r7-CW8GR79l-mmLqMhc-Sa",
                                    "discovery": "https://samples.auth0.com/.well-known/openid-configuration",
                                    "redirect_uri": "https://iresty.com",
                                    "ssl_verify": "no",
                                    "timeout": 10000,
                                    "bearer_only": true,
                                    "scope": "apisix",
                                    "public_key": "-----BEGIN PUBLIC KEY-----
MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANW16kX5SMrMa2t7F2R1w6Bk/qpjS4QQ
hnrbED3Dpsl9JXAx90MYsIWp51hBxJSE/EPVK8WF/sjHK1xQbEuDfEECAwEAAQ==
-----END PUBLIC KEY-----",
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
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 9: access introspection with correct token
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJfT3B2Wm5lSkR3T0NqczZSZmFObjdIc0lKZmRhMWxfU0ZkYUo2SU1hV0k0In0.eyJqdGkiOiJjNGY4ZWNjNS0wZWYzLTQzYWYtOTJkZS0xMmY5YjJhNDhiYzAiLCJleHAiOjE1OTE4MjMyOTgsIm5iZiI6MCwiaWF0IjoxNTkxNzg3Mjk4LCJpc3MiOiJodHRwczovL2VmYWN0b3J5LXNlY3VyaXR5LXBvcnRhbC5zYWx6YnVyZ3Jlc2VhcmNoLmF0L2F1dGgvcmVhbG1zL0NBTVBBSUdOX1JFQUxNIiwiYXVkIjoiYWNjb3VudCIsInN1YiI6IjUxZGUzNzQ4LTZiNzctNGZmNC04ZDE5LWY1YTg4NThjYWZkMyIsInR5cCI6IkJlYXJlciIsImF6cCI6IkNBTVBBSUdOX0NMSUVOVCIsImF1dGhfdGltZSI6MCwic2Vzc2lvbl9zdGF0ZSI6ImQxZDliMWQ1LTk1ZWQtNDI4NS04NTEzLWYwOGEwNmVjNjM1NyIsImFjciI6IjEiLCJhbGxvd2VkLW9yaWdpbnMiOlsiKiJdLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsib2ZmbGluZV9hY2Nlc3MiLCJ1bWFfYXV0aG9yaXphdGlvbiIsImN1c3RvbWVyLWFkdmVydGlzZXIiXX0sInJlc291cmNlX2FjY2VzcyI6eyJhY2NvdW50Ijp7InJvbGVzIjpbIm1hbmFnZS1hY2NvdW50IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6ImVtYWlsIHByb2ZpbGUiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsInByZWZlcnJlZF91c2VybmFtZSI6ImFkdmVydGlzZXJfdXNlciJ9.A3R-JABGHLNIPcjibrUFmJG8Nzm3gLjCYTne9ibP0LXrM9cJRdmjK75g9wtSfI4a313S5TwyG_Y-4OXfy0IeI4GgAv2q7mGgP4dKplHnGO_4vhEmFqbiEI2__2saAWatmgTz8LV2sA1D0B9zU-hHy7MzaLVXPvVXFG3lACB0ecmLRweeVRRQQQRibe9lh0VrOBoJQfl-zOc8GWVagpYrmJlr-zMMqm5MYCE1rNPwA28IfeAT8-wQxwqPTMq01q2bHU3qFqWDITEUcJIwowriKrSY1uU6t9c6Roff6HJKl6BOLoXLo5jTuPtBSfLhBU9BWceYnJ9m-o9TVenijI1vFQ",
                    }
                })
            ngx.status = res.status
            if res.status == 200 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 10: access introspection with wrong token
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9" ..
                        ".eyJkYXRhMSI6IkRhdGEgMSIsImlhdCI6MTU4NTEyMjUwMiwiZXhwIjoxOTAwNjk" ..
                        "4NTAyLCJhdWQiOiJodHRwOi8vbXlzb2Z0Y29ycC5pbiIsImlzcyI6Ik15c29mdCB" ..
                        "jb3JwIiwic3ViIjoic29tZUB1c2VyLmNvbSJ9.u1ISx7JbuK_GFRIUqIMP175FqX" ..
                        "RyF9V7y86480Q4N3jNxs3ePbc51TFtIHDrKttstU4Tub28PYVSlr-HXfjo7",
                    }
                })
            ngx.status = res.status
            if res.status == 200 then
                ngx.say(true)
            end
        }
    }
--- request
GET /t
--- error_code: 401
--- error_log
jwt signature verification failed
