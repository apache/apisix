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
                whitelist = {
                    "jack1",
                    "jack2"
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("cjson").encode(conf))
        }
    }
--- request
GET /t
--- response_body
{"rejected_code":403,"type":"consumer_name","whitelist":["jack1","jack2"]}
--- no_error_log
[error]



=== TEST 2: whitelist and blacklist mutual exclusive
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.consumer-restriction")
            local ok, err = plugin.check_schema({whitelist={"jack1"}, blacklist={"jack2"}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
value should match only one schema, but matches both schemas 1 and 2
done
--- no_error_log
[error]



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
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack1",
                            "plugins": {
                                "basic-auth": {
                                    "username": "jack2019",
                                    "password": "123456"
                                }
                            }
                        }
                    },
                    "action": "set"
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
--- no_error_log
[error]



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
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack2",
                            "plugins": {
                                "basic-auth": {
                                    "username": "jack2020",
                                    "password": "123456"
                                }
                            }
                        }
                    },
                    "action": "set"
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
--- no_error_log
[error]



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
--- no_error_log
[error]



=== TEST 6: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}
--- no_error_log
[error]



=== TEST 7: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world
--- no_error_log
[error]



=== TEST 8: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer_name is forbidden."}
--- no_error_log
[error]



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
--- no_error_log
[error]



=== TEST 10: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}
--- no_error_log
[error]



=== TEST 11: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 403
--- response_body
{"message":"The consumer_name is forbidden."}
--- no_error_log
[error]



=== TEST 12: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- response_body
hello world
--- no_error_log
[error]



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
--- no_error_log
[error]



=== TEST 14: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 15: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 16: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



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
--- no_error_log
[error]



=== TEST 18: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 19: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 20: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- error_code: 401
--- response_body
{"message":"Missing authentication or identity verification."}
--- no_error_log
[error]



=== TEST 21: remove consumer-restriction
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
--- no_error_log
[error]



=== TEST 22: verify jack1
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMTk6MTIzNDU2
--- response_body
hello world
--- no_error_log
[error]



=== TEST 23: verify jack2
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazIwMjA6MTIzNDU2
--- response_body
hello world
--- no_error_log
[error]



=== TEST 24: verify unauthorized
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 25: create service (id:1)
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new service 001"
                        },
                        "key": "/apisix/services/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 26: add consumer with plugin hmac-auth and consumer-restriction, and set whitelist
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
                            "access_key": "my-access-key",
                            "secret_key": "my-secret-key"
                        },
                        "consumer-restriction": {
                            "type": "service_id",
                            "whitelist": [ "1" ],
                            "rejected_code": 401
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "hmac-auth": {
                                    "access_key": "my-access-key",
                                    "secret_key": "my-secret-key",
                                    "algorithm": "hmac-sha256",
                                    "clock_skew": 0
                                },
                                "consumer-restriction": {
                                    "type": "service_id",
                                    "whitelist": [ "1" ],
                                    "rejected_code": 401
                                }
                            }
                        }
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 27: Route binding `hmac-auth` plug-in and whitelist `service_id`
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

                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/hello",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "service_id": 1,
                            "plugins": {
                                "hmac-auth": {}
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 28: verify: valid whitelist `service_id`
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
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. gmt .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
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
--- no_error_log
[error]



=== TEST 29: create service (id:2)
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "new service 002"
                        },
                        "key": "/apisix/services/2"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 30: Route binding `hmac-auth` plug-in and invalid whitelist `service_id`
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

                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/hello",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "service_id": 2,
                            "plugins": {
                                "hmac-auth": {}
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 31: verify: invalid whitelist `service_id`
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
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. gmt .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
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
--- no_error_log
[error]



=== TEST 32: add consumer with plugin hmac-auth and consumer-restriction, and set blacklist
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
                            "access_key": "my-access-key",
                            "secret_key": "my-secret-key"
                        },
                        "consumer-restriction": {
                            "type": "service_id",
                            "blacklist": [ "1" ],
                            "rejected_code": 401
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "jack",
                            "plugins": {
                                "hmac-auth": {
                                    "access_key": "my-access-key",
                                    "secret_key": "my-secret-key",
                                    "algorithm": "hmac-sha256",
                                    "clock_skew": 0
                                },
                                "consumer-restriction": {
                                    "type": "service_id",
                                    "blacklist": [ "1" ],
                                    "rejected_code": 401
                                }
                            }
                        }
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 33: Route binding `hmac-auth` plug-in and blacklist `service_id`
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

                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/hello",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "service_id": 1,
                            "plugins": {
                                "hmac-auth": {}
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 34: verify: valid blacklist `service_id`
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
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. gmt .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
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
--- no_error_log
[error]



=== TEST 35: Route binding `hmac-auth` plug-in and invalid blacklist `service_id`
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

                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/hello",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "service_id": 2,
                            "plugins": {
                                "hmac-auth": {}
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 36: verify: invalid blacklist `service_id`
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
        local access_key = "my-access-key"
        local custom_header_a = "asld$%dfasf"
        local custom_header_b = "23879fmsldfk"

        local signing_string = "GET" .. "/hello" ..  "" ..
            access_key .. gmt .. custom_header_a .. custom_header_b

        local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
        core.log.info("signature:", ngx_encode_base64(signature))
        local headers = {}
        headers["X-HMAC-SIGNATURE"] = ngx_encode_base64(signature)
        headers["X-HMAC-ALGORITHM"] = "hmac-sha256"
        headers["Date"] = gmt
        headers["X-HMAC-ACCESS-KEY"] = access_key
        headers["X-HMAC-SIGNED-HEADERS"] = "x-custom-header-a;x-custom-header-b"
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
--- no_error_log
[error]



=== TEST 37: delete: route (id: 1)
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
--- no_error_log
[error]



=== TEST 38: delete: `service_id` is 1
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
--- no_error_log
[error]



=== TEST 39: delete: `service_id` is 2
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
--- no_error_log
[error]
