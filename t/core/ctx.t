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

repeat_each(2);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("remote_addr: ", ctx.var["remote_addr"])
            ngx.say("server_port: ", ctx.var["server_port"])
        }
    }
--- request
GET /t
--- response_body
remote_addr: 127.0.0.1
server_port: 1984
--- no_error_log
[error]



=== TEST 2: http header + arg
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("http_host: ", ctx.var["http_host"])
            ngx.say("arg_a: ", ctx.var["arg_a"])
        }
    }
--- request
GET /t?a=aaa
--- response_body
http_host: localhost
arg_a: aaa
--- no_error_log
[error]



=== TEST 3: cookie + no cookie
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("cookie_host: ", ctx.var["cookie_host"])
        }
    }
--- request
GET /t?a=aaa
--- response_body
cookie_host: nil
--- error_log
failed to fetch cookie value by key: cookie_host error: no cookie found in the current request



=== TEST 4: cookie
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("cookie_a: ", ctx.var["cookie_a"])
            ngx.say("cookie_b: ", ctx.var["cookie_b"])
            ngx.say("cookie_c: ", ctx.var["cookie_c"])
            ngx.say("cookie_d: ", ctx.var["cookie_d"])
        }
    }
--- more_headers
Cookie: a=a; b=bb; c=ccc
--- request
GET /t?a=aaa
--- response_body
cookie_a: a
cookie_b: bb
cookie_c: ccc
cookie_d: nil
--- no_error_log
[error]



=== TEST 5: key is nil
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("cookie_a: ", ctx.var[nil])
        }
    }
--- more_headers
Cookie: a=a; b=bb; c=ccc
--- request
GET /t?a=aaa
--- error_code: 500
--- error_log
invalid argument, expect string value



=== TEST 6: key is number
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ctx = {}
            core.ctx.set_vars_meta(ctx)

            ngx.say("cookie_a: ", ctx.var[2222])
        }
    }
--- more_headers
Cookie: a=a; b=bb; c=ccc
--- request
GET /t?a=aaa
--- error_code: 500
--- error_log
invalid argument, expect string value



=== TEST 7: add route and get `route_id`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"route_id: \", ngx.ctx.api_ctx.var.route_id) end"]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
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
--- no_error_log
[error]



=== TEST 8: `url` exist and `route_id` is 1
--- request
GET /hello
--- response_body
hello world
--- error_log
route_id: 1
--- no_error_log
[error]



=== TEST 9: create a service and `service_id` is 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "desc": "new_service"
                }]],
                [[{
                    "node": {
                        "value": {
                            "desc": "new_service"
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



=== TEST 10: the route object not bind any service object
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"service_id: \", ngx.ctx.api_ctx.var.service_id or 'empty route_id') end"]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "uri": "/hello"
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



=== TEST 11: service_id is empty
--- request
GET /hello
--- response_body
hello world
--- error_log
service_id: empty route_id
--- no_error_log
[error]



=== TEST 12: update route and binding service_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "service_id": 1,
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"service_id: \", ngx.ctx.api_ctx.var.service_id) end"]
                        }
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    },
                    "uri": "/hello"
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



=== TEST 13: service_id is 1
--- request
GET /hello
--- response_body
hello world
--- error_log
service_id: 1
--- no_error_log
[error]



=== TEST 14: create consumer and bind key-auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "consumer_jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
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



=== TEST 15: create route and consumer_name is consumer_jack
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
                    "uri": "/hello",
                    "plugins": {
                        "key-auth": {},
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"consumer_name: \", ngx.ctx.api_ctx.var.consumer_name) end"]
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



=== TEST 16: consumer_name is `consumer_jack`
--- request
GET /hello
--- more_headers
apikey: auth-jack
--- response_body
hello world
--- error_log
consumer_name: consumer_jack
--- no_error_log
[error]



=== TEST 17: update the route, and the consumer_name is nil
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
                    "uri": "/hello",
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"consumer_name: \", ngx.ctx.api_ctx.var.consumer_name or 'consumer_name is nil') end"]
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



=== TEST 18: consumer_name is empty
--- request
GET /hello
--- response_body
hello world
--- error_log
consumer_name: consumer_name is nil
--- no_error_log
[error]



=== TEST 19: create route and consumer_name is consumer_jack
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
                    "uri": "/hello",
                    "plugins": {
                        "key-auth": {},
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"consumer_name: \", ngx.ctx.api_ctx.var.consumer_name) end"]
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



=== TEST 20: consumer_name is `consumer_jack`
--- request
GET /hello
--- more_headers
apikey: auth-jack
--- response_body
hello world
--- error_log
consumer_name: consumer_jack
--- no_error_log
[error]



=== TEST 21: update the route, and the consumer_name is nil
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
                    "uri": "/hello",
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"consumer_name: \", ngx.ctx.api_ctx.var.consumer_name or 'consumer_name is nil') end"]
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



=== TEST 22: consumer_name is nil
--- request
GET /hello
--- response_body
hello world
--- error_log
consumer_name: consumer_name is nil
--- no_error_log
[error]



=== TEST 23: add plugin metadata `service_name`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "service_name": "$service_name"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "log_format": {
                                "service_name": "$service_name"
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



=== TEST 24: add `http-logger` plugin on service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "name": "ctx_var-support-service_name",
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "batch_max_size": 1,
                            "max_retry_count": 1,
                            "retry_delay": 2,
                            "buffer_duration": 2,
                            "concat_method": "json"
                        }
                    },
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



=== TEST 25: route binding service and concat_method is json
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": 1,
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
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
--- no_error_log
[error]



=== TEST 26: hit route and report http logger
--- request
GET /hello
--- response_body
hello world
--- error_log eval
qr/request log: \{"route_id":"1","service_id":"1","service_name":"ctx_var-support-service_name"\}/



=== TEST 27: log_format is configured with `service_name`, but there is no matching service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "batch_max_size": 1,
                            "max_retry_count": 1,
                            "retry_delay": 2,
                            "buffer_duration": 2,
                            "concat_method": "json"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
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
--- no_error_log
[error]



=== TEST 28: hit route but there is no matching service
--- request
GET /hello
--- response_body
hello world
--- error_log eval
qr/request log: \{"route_id":"1"\}/



=== TEST 29: add plugin metadata `route_name`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "route_name": "$route_name"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "log_format": {
                                "route_name": "$route_name"
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



=== TEST 30: sanity, batch_max_size=1 and concat_method is json
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "name": "ctx_var-support-route_name",
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "batch_max_size": 1,
                            "max_retry_count": 1,
                            "retry_delay": 2,
                            "buffer_duration": 2,
                            "concat_method": "json"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
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
--- no_error_log
[error]



=== TEST 31: hit route and report http logger
--- request
GET /hello
--- response_body
hello world
--- error_log eval
qr/request log: \{"route_id":"1","route_name":"ctx_var-support-route_name"\}/



=== TEST 32: missing `name` field, batch_max_size=1 and concat_method is json
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "batch_max_size": 1,
                            "max_retry_count": 1,
                            "retry_delay": 2,
                            "buffer_duration": 2,
                            "concat_method": "json"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
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
--- no_error_log
[error]



=== TEST 33: hit route and report http logger
--- request
GET /hello
--- response_body
hello world
--- error_log eval
qr/request log: \{"route_id":"1"\}/



=== TEST 34: add metadata, service and route, and the service is bound to the route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "route_name": "$route_name",
                        "service_name": "$service_name"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "log_format": {
                                "route_name": "$route_name",
                                "service_name": "$service_name"
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "name": "my_service",
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "batch_max_size": 1,
                            "max_retry_count": 1,
                            "retry_delay": 2,
                            "buffer_duration": 2,
                            "concat_method": "json"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "name": "my_route",
                    "uri": "/hello",
                    "service_id": 1,
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



=== TEST 35: hit route and route_name and service_name are different
--- request
GET /hello
--- response_body
hello world
--- error_log eval
qr/request log: \{"route_id":"1","route_name":"my_route","service_id":"1","service_name":"my_service"\}/
