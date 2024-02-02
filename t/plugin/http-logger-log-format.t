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
                }]]
                )
            if code >=300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



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
                                "uri": "http://127.0.0.1:3001",
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

            local code, _, body2 = t("/hello", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: report http logger
--- exec
tail -n 1 ci/pod/vector/http.log
--- response_body eval
qr/.*route_id":"1".*/



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
                                "uri": "http://127.0.0.1:3001",
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

            local code, _, body2 = t("/hello", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: report http logger
--- exec
tail -n 1 ci/pod/vector/http.log
--- response_body eval
qr/"\@timestamp":"20/



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
                                "uri": "http://127.0.0.1:3001",
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

            local code, _, body2 = t("/hello", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 7: report http logger
--- exec
tail -n 1 ci/pod/vector/http.log
--- response_body eval
qr/"route_id":"1"/



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
                                "uri": "http://127.0.0.1:3001",
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

            local code, _, body2 = t("/hello", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, _, body2 = t("/hello", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 9: report http logger to confirm two json in array
--- exec
tail -n 1 ci/pod/vector/http.log
--- response_body eval
qr/\[\{.*?\},\{.*?\}\]/



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
                                "uri": "http://127.0.0.1:3001",
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

            local code, _, _ = t("/hello", "GET",null,null,{apikey = "auth-one"})
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 13: check logs
--- exec
tail -n 1 ci/pod/vector/http.log
--- response_body eval
qr/"consumer":\{"username":"jack"\}/
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



=== TEST 15: use custom variable in the logger
--- extra_init_by_lua
    local core = require "apisix.core"

    core.ctx.register_var("a6_route_labels", function(ctx)
        local route = ctx.matched_route and ctx.matched_route.value
        if route and route.labels then
            return route.labels
        end
        return nil
    end)
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
                                "uri": "http://127.0.0.1:3001",
                                "batch_max_size": 1,
                                "concat_method": "json"
                            }
                        },
                        "labels":{
                            "key":"testvalue"
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

            local code, _, body2 = t("/hello", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 16: hit route and report http logger
--- exec
tail -n 1 ci/pod/vector/http.log
--- response_body eval
qr/.*testvalue.*/



=== TEST 17: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:3001",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
                                "concat_method": "new_line",
                                "log_format": {
                                    "x_ip": "$remote_addr"
                                }
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

            local code, _, body2 = t("/hello", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 18: hit route and report http logger
--- exec
tail -n 1 ci/pod/vector/http.log
--- response_body eval
qr/"x_ip":"127.0.0.1".*\}/
