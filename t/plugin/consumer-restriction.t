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
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.consumer-restriction")
            local conf = {
        title = "whitelist",
        whitelist = {
                    "jack1",
                    "jack2"
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- request
GET /t
--- response_body
{"rejected_code":403,"title":"whitelist","type":"consumer_name","whitelist":["jack1","jack2"]}



=== TEST 2: blacklist > whitelist > allowed_by_methods
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.consumer-restriction")
            local ok, err = plugin.check_schema({whitelist={"jack1"}, blacklist={"jack2"}, allowed_by_methods={}})
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



=== TEST 3: add consumer jack1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack1",
                    "plugins": {
                        "basic-auth": {
                            "username": "jack2019",
                            "password": "123456"
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



=== TEST 4: add consumer jack2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack2",
                    "plugins": {
                        "basic-auth": {
                            "username": "jack2020",
                            "password": "123456"
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



=== TEST 5: set whitelist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "whitelist": [
                                     "jack1"
                                 ]
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



=== TEST 6: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 7: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world



=== TEST 8: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer_name is forbidden."}



=== TEST 9: set blacklist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "blacklist": [
                                     "jack1"
                                 ],
                                 "rejected_msg": "request is forbidden"
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



=== TEST 10: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 11: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"request is forbidden"}



=== TEST 12: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- response_body
hello world



=== TEST 13: set whitelist without authorization
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "consumer-restriction": {
                                 "whitelist": [
                                     "jack1"
                                 ]
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



=== TEST 14: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"The request is rejected, please check the consumer_name for this request"}



=== TEST 15: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"The request is rejected, please check the consumer_name for this request"}



=== TEST 16: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"The request is rejected, please check the consumer_name for this request"}



=== TEST 17: set blacklist without authorization
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "consumer-restriction": {
                                 "blacklist": [
                                     "jack1"
                                 ]
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



=== TEST 18: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"The request is rejected, please check the consumer_name for this request"}



=== TEST 19: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"The request is rejected, please check the consumer_name for this request"}



=== TEST 20: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"The request is rejected, please check the consumer_name for this request"}



=== TEST 21: set allowed_by_methods
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "allowed_by_methods":[{
                                    "user":"jack1",
                                    "methods":["POST"]
                                 }]
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



=== TEST 22: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer_name is forbidden."}



=== TEST 23: set allowed_by_methods
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "allowed_by_methods":[{
                                    "user": "jack1",
                                    "methods": ["POST","GET"]
                                }]
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



=== TEST 24: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world



=== TEST 25: test blacklist priority
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "blacklist": [
                                     "jack1"
                                 ],
                                 "allowed_by_methods":[{
                                    "user": "jack1",
                                    "methods": ["POST","GET"]
                                }]
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



=== TEST 26: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer_name is forbidden."}



=== TEST 27: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- response_body
hello world



=== TEST 28: whitelist blacklist priority
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "consumer-restriction": {
                                 "whitelist": ["jack1"],
                                 "allowed_by_methods":[{
                                    "user":"jack1",
                                    "methods":["POST"]
                                }]
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



=== TEST 29: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world



=== TEST 30: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer_name is forbidden."}



=== TEST 31: remove consumer-restriction
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
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



=== TEST 32: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world



=== TEST 33: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- response_body
hello world



=== TEST 34: verify unauthorized
--- request
GET /hello
--- response_body
hello world



=== TEST 35: create service (id:1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new service 001"
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



=== TEST 36: add consumer with plugin hmac-auth and consumer-restriction, and set whitelist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "hmac-auth": {
                            "key_id": "my-access-key",
                            "secret_key": "my-secret-key"
                        },
                        "consumer-restriction": {
                            "type": "service_id",
                            "whitelist": [ "1" ],
                            "rejected_code": 401
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



=== TEST 37: Route binding `hmac-auth` plug-in and whitelist `service_id`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "service_id": 1,
                    "uri": "/hello",
                    "plugins": {
                        "hmac-auth": {}
                    }

                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 38: verify: valid whitelist `service_id`
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
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
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



=== TEST 39: create service (id:2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/2',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new service 002"
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



=== TEST 40: Route binding `hmac-auth` plug-in and invalid whitelist `service_id`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "service_id": 2,
                    "uri": "/hello",
                    "plugins": {
                        "hmac-auth": {}
                    }

                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 41: verify: invalid whitelist `service_id`
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
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
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
            nil,
            headers
        )
        if code >= 300 then
            ngx.status = code
        end

        ngx.say(body)
    }
}
--- request
GET /t
--- error_code: 401
--- response_body eval
qr/\{"message":"The service_id is forbidden."\}/



=== TEST 42: add consumer with plugin hmac-auth and consumer-restriction, and set blacklist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "hmac-auth": {
                            "key_id": "my-access-key",
                            "secret_key": "my-secret-key"
                        },
                        "consumer-restriction": {
                            "type": "service_id",
                            "blacklist": [ "1" ],
                            "rejected_code": 401
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 43: Route binding `hmac-auth` plug-in and blacklist `service_id`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "service_id": 1,
                    "uri": "/hello",
                    "plugins": {
                        "hmac-auth": {}
                    }

                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 44: verify: valid blacklist `service_id`
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
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
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
            nil,
            headers
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- error_code: 401
--- response_body eval
qr/\{"message":"The service_id is forbidden."\}/



=== TEST 45: Route binding `hmac-auth` plug-in and invalid blacklist `service_id`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "service_id": 2,
                    "uri": "/hello",
                    "plugins": {
                        "hmac-auth": {}
                    }

                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 46: verify: invalid blacklist `service_id`
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
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
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
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



=== TEST 47: update consumer with plugin hmac-auth and consumer-restriction, and set whitelist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "hmac-auth": {
                            "key_id": "my-access-key",
                            "secret_key": "my-secret-key"
                        },
                        "consumer-restriction": {
                            "type": "route_id",
                            "whitelist": [ "1" ],
                            "rejected_code": 401
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 48: verify: valid whitelist `route_id`
--- config
location /t {
    content_by_lua_block {
        local ngx_time = ngx.time()
        local ngx_http_time = ngx.http_time
        local core = require("apisix.core")
        local t = require("lib.test_admin")
        local hmac = require("resty.hmac")
        local ngx_encode_base64 = ngx.encode_base64
        local secret_key = "my-secret-key"
        local gmt = ngx_http_time(ngx_time)
        local key_id = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = {
            key_id,
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
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



=== TEST 49: update consumer with plugin hmac-auth and consumer-restriction, and set blacklist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "hmac-auth": {
                            "key_id": "my-access-key",
                            "secret_key": "my-secret-key"
                        },
                        "consumer-restriction": {
                            "type": "route_id",
                            "blacklist": [ "1" ],
                            "rejected_code": 401
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 50: verify: valid blacklist `route_id`
--- config
location /t {
    content_by_lua_block {
        local ngx_time   = ngx.time
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
            "GET /hello",
            "date: " .. gmt,
            "x-custom-header-a: " .. custom_header_a,
            "x-custom-header-b: " .. custom_header_b
        }
        signing_string = core.table.concat(signing_string, "\n") .. "\n"

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["Date"] = gmt
        headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
        headers["x-custom-header-a"] = custom_header_a
        headers["x-custom-header-b"] = custom_header_b

        local code, body = t.test('/hello',
            ngx.HTTP_GET,
            "",
            nil,
            headers
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- error_code: 401
--- response_body eval
qr/\{"message":"The route_id is forbidden."\}/



=== TEST 51: delete: route (id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t( '/apisix/admin/routes/1', ngx.HTTP_DELETE )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 52: delete: `service_id` is 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t( '/apisix/admin/services/1', ngx.HTTP_DELETE )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 53: delete: `service_id` is 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t( '/apisix/admin/services/2', ngx.HTTP_DELETE )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
