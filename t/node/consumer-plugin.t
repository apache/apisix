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

=== TEST 1: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        },
                        "key-auth": {
                            "key": "auth-one"
                        }
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



=== TEST 2: enable key auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {}
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
--- request
GET /t
--- response_body
passed



=== TEST 3: invalid consumer
--- request
GET /hello
--- more_headers
apikey: 123
--- error_code: 401
--- response_body
{"message":"Invalid API key in request"}



=== TEST 4: valid consumer
--- request
GET /hello
--- more_headers
apikey: auth-one
--- response_body
hello world



=== TEST 5: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-one
--- error_code eval
[200, 200, 503, 503]



=== TEST 6: missing auth plugins (not allow)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"require one auth plugin"}



=== TEST 7: use the new configuration after the consumer's configuration is updated
--- config
    location /t {
        content_by_lua_block {
            local function test()
                local json_encode = require("toolkit.json").encode
                local http = require "resty.http"
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

                local status_count = {}
                for i = 1, 5 do
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri,
                        {
                            method = "GET",
                            headers = {
                                apikey = "auth-one",
                            }
                        }
                    )
                    if not res then
                        ngx.say(err)
                        return
                    end

                    local status = tostring(res.status)
                    status_count[status] = (status_count[status] or 0) + 1
                end
                ngx.say(json_encode(status_count))
            end

            test()

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "limit-count": {
                            "count": 4,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        },
                        "key-auth": {
                            "key": "auth-one"
                        }
                    }
                }]]
            )

            ngx.sleep(0.1)

            test()
        }
    }
--- request
GET /t
--- response_body
{"200":2,"503":3}
{"200":4,"503":1}



=== TEST 8: consumer with multiple auth plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/consumers',
                 ngx.HTTP_PUT,
                 [[{
                    "username": "John_Doe",
                    "desc": "new consumer",
                    "plugins": {
                            "key-auth": {
                                "key": "consumer-plugin-John_Doe"
                            },
                            "hmac-auth": {
                                "access_key": "my-access-key",
                                "secret_key": "my-secret-key",
                                "clock_skew": 1
                            }
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



=== TEST 9: bind to routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {}
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
                ngx.log(ngx.ERR, "failed to bind route 1")
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/status"
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



=== TEST 10: hit consumer, key-auth
--- request
GET /hello
--- more_headers
apikey: consumer-plugin-John_Doe
--- response_body
hello world
--- error_log
find consumer John_Doe



=== TEST 11: hit consumer, hmac-auth
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64

        local secret_key = "my-secret-key"
        local timestamp = ngx_time()
        local gmt = ngx_http_time(timestamp)
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            key_id,
            "GET /status",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"
        core.log.info("signing_string:", signing_string)

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/status',
            ngx.HTTP_GET,
            nil,
            nil,
            headers
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed
--- error_log
find consumer John_Doe



=== TEST 12: the plugins bound on the service should use the latest configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username":"jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "header": "Authorization"
                        },
                        "proxy-rewrite": {
                            "uri": "/hello1"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": [
                        "GET"
                    ],
                    "uri": "/hello",
                    "service_id": "1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local headers = {
                ["Authorization"] = "auth-jack"
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.print(res.body)

            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "header": "Authorization"
                        },
                        "proxy-rewrite": {
                            "uri": "/server_port"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            local res, err = httpc:request_uri(uri, {headers = headers})
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body
hello1 world
1980
