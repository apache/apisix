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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "host": "$host",
                        "@timestamp": "$time_iso8601",
                        "client_ip": "$remote_addr"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "log_format": {
                                "host": "$host",
                                "@timestamp": "$time_iso8601",
                                "client_ip": "$remote_addr"
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



=== TEST 2: sanity, batch_max_size=1 and concat_method is new_line
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
                                "inactive_timeout": 2,
                                "concat_method": "new_line"
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



=== TEST 3: hit route and report http logger
--- request
GET /hello
--- response_body
hello world
--- wait: 0.5
--- no_error_log
[error]
--- error_log eval
qr/request log: \{.*route_id":"1".*\}/



=== TEST 4: sanity, batch_max_size=2 and concat_method is new_line
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
                                "batch_max_size": 2,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
                                "concat_method": "new_line"
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



=== TEST 5: hit route and report http logger
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        for i = 1, 2 do
            t('/hello', ngx.HTTP_GET)
        end

        ngx.sleep(3)
        ngx.say("done")
    }
}
--- request
GET /t
--- error_code: 200
--- no_error_log
[error]
--- grep_error_log eval
qr/"\@timestamp":"20/
--- grep_error_log_out
"@timestamp":"20
"@timestamp":"20



=== TEST 6: sanity, batch_max_size=1 and concat_method is json
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
                                "inactive_timeout": 2,
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



=== TEST 7: hit route and report http logger
--- request
GET /hello
--- response_body
hello world
--- wait: 0.5
--- no_error_log
[error]
--- error_log eval
qr/request log: \{"\@timestamp":.*,"client_ip":"127.0.0.1","host":"localhost","route_id":"1"\}/



=== TEST 8: sanity, batch_max_size=2 and concat_method is json
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
                                "batch_max_size": 2,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
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



=== TEST 9: hit route and report http logger
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        for i = 1, 2 do
            t('/hello', ngx.HTTP_GET)
        end

        ngx.sleep(3)
        ngx.say("done")
    }
}
--- request
GET /t
--- error_code: 200
--- no_error_log
[error]
--- error_log eval
qr/request log: \[\{"\@timestamp":".*","client_ip":"127.0.0.1","host":"127.0.0.1","route_id":"1"\},\{"\@timestamp":".*","client_ip":"127.0.0.1","host":"127.0.0.1","route_id":"1"\}\]/



=== TEST 10: remove plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_DELETE
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



=== TEST 11: remove route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)

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



=== TEST 12: check default log format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                 ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        }
                    }
                }]]
                )

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1982/log",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            },
                            "key-auth": {}
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



=== TEST 13: hit
--- request
GET /hello
--- more_headers
apikey: auth-one
--- grep_error_log eval
qr/request log: \{.+\}/
--- grep_error_log_out eval
qr/\Q{"apisix_latency":\E[^,]+\Q,"client_ip":"127.0.0.1","consumer":{"username":"jack"},"latency":\E[^,]+\Q,"request":{"headers":{"apikey":"auth-one","connection":"close","host":"localhost"},"method":"GET","querystring":{},"size":\E\d+\Q,"uri":"\/hello","url":"http:\/\/localhost:1984\/hello"},"response":{"headers":{"connection":"close","content-length":"\E\d+\Q","content-type":"text\/plain","server":"\E[^"]+\Q"},"size":\E\d+\Q,"status":200},"route_id":"1","server":{"hostname":"\E[^"]+\Q","version":"\E[^"]+\Q"},"service_id":"","start_time":\E\d+\Q,"upstream":"127.0.0.1:1982","upstream_latency":\E[^,]+\Q}\E/
--- wait: 0.5



=== TEST 14: multi level nested expr conditions
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.http-logger")
            local ok, err = plugin.check_schema({
                 uri = "http://127.0.0.1",
                 include_resp_body = true,
                 include_resp_body_expr = {
                    {"http_content_length", "<", 1024},
                    {"http_content_type", "in", {"application/xml", "application/json", "text/plain", "text/xml"}}
                 }
            })
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



=== TEST 15: use custom variable in the logger
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "host": "$host",
                        "labels": "$a6_route_labels",
                        "client_ip": "$remote_addr"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return body
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1980/log",
                                "batch_max_size": 1,
                                "concat_method": "json"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "labels": {
                            "k": "v"
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



=== TEST 16: hit route and report http logger
--- extra_init_by_lua
    local core = require "apisix.core"

    core.ctx.register_var("a6_route_labels", function(ctx)
        local route = ctx.matched_route and ctx.matched_route.value
        if route and route.labels then
            return route.labels
        end
        return nil
    end)
--- request
GET /hello
--- response_body
hello world
--- wait: 0.5
--- no_error_log
[error]
--- error_log eval
qr/request log: \{"client_ip":"127.0.0.1","host":"localhost","labels":\{"k":"v"\},"route_id":"1"\}/
