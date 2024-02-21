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
            local plugin = require("apisix.plugins.syslog")
            local ok, err = plugin.check_schema({
                 host = "127.0.0.1",
                 port = 5140,
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



=== TEST 2: missing port
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.syslog")
            local ok, err = plugin.check_schema({host = "127.0.0.1"})
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "port" is required
done



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.syslog")
            local ok, err = plugin.check_schema({
                 host = "127.0.0.1",
                 port = "5140",
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
property "port" validation failed: wrong type: expected integer, got string
done



=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "host" : "127.0.0.1",
                                "port" : 5140
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
--- request
GET /t
--- response_body
passed



=== TEST 5: access
--- request
GET /hello
--- response_body
hello world
--- wait: 0.2



=== TEST 6: flush manually
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.syslog")
            local logger_socket = require("resty.logger.socket")
            local logger, err = logger_socket:new({
                    host = "127.0.0.1",
                    port = 5140,
                    flush_limit = 100,
            })

            local bytes, err = logger:log("abc")
            if err then
                ngx.log(ngx.ERR, err)
            end

            local bytes, err = logger:log("efg")
            if err then
                ngx.log(ngx.ERR, err)
            end

            local ok, err = plugin.flush_syslog(logger)
            if not ok then
                ngx.say("failed to flush syslog: ", err)
                return
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 7: small flush_limit, instant flush
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                -- before 2.13.0, timeout is incorrectly treated as inactive_timeout
                [[{
                    "plugins": {
                        "syslog": {
                                "host" : "127.0.0.1",
                                "port" : 5140,
                                "flush_limit" : 1,
                                "inactive_timeout": 1
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

            -- wait etcd sync
            ngx.sleep(0.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say("failed request: ", err)
                return
            end

            if res.status >= 300 then
                ngx.status = res.status
            end
            ngx.print(res.body)

            -- wait flush log
            ngx.sleep(2.5)
        }
    }
--- request
GET /t
--- response_body
passed
hello world
--- error_log
try to lock with key route#1
unlock with key route#1
--- timeout: 5



=== TEST 8: check log
--- exec
tail -n 1 ci/pod/vector/syslog-tcp.log
--- response_body eval
qr/.*apisix_latency.*/



=== TEST 9: check plugin configuration updating
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body1 = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "host": "127.0.0.1",
                                "port": 5044,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, _, body2 = t("/opentracing", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, body3 = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "host": "127.0.0.1",
                                "port": 5045,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, _, body4 = t("/opentracing", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.print(body1)
            ngx.print(body2)
            ngx.print(body3)
            ngx.print(body4)
        }
    }
--- request
GET /t
--- wait: 0.5
--- response_body
passedopentracing
passedopentracing
--- grep_error_log eval
qr/sending a batch logs to 127.0.0.1:(\d+)/
--- grep_error_log_out
sending a batch logs to 127.0.0.1:5044
sending a batch logs to 127.0.0.1:5045



=== TEST 10: add log format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/syslog',
                 ngx.HTTP_PUT,
                 [[{
                    "log_format": {
                        "host": "$host",
                        "client_ip": "$remote_addr",
                        "upstream": "$upstream_addr"
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



=== TEST 11: Add route and Enable Syslog Plugin, batch_max_size=1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "batch_max_size": 1,
                                "disable": false,
                                "flush_limit": 1,
                                "host" : "127.0.0.1",
                                "port" : 5140
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
--- request
GET /t
--- response_body
passed



=== TEST 12: hit route and report sys logger
--- extra_init_by_lua
    local syslog = require("apisix.plugins.syslog.init")
    local json = require("apisix.core.json")
    local log = require("apisix.core.log")
    local old_f = syslog.push_entry
    syslog.push_entry = function(conf, ctx, entry)
        log.info("syslog-log-format => " ..  json.encode(entry))
        return old_f(conf, ctx, entry)
    end
--- request
GET /hello
--- response_body
hello world
--- wait: 0.5
--- no_error_log
[error]
--- error_log eval
qr/syslog-log-format.*\{.*"upstream":"127.0.0.1:\d+"/



=== TEST 13: check log
--- exec
tail -n 1 ci/pod/vector/syslog-tcp.log
--- response_body eval
qr/.*\"host\":\"localhost\".*/



=== TEST 14: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "batch_max_size": 1,
                                "flush_limit": 1,
                                "log_format": {
                                    "vip": "$remote_addr"
                                },
                                "host" : "127.0.0.1",
                                "port" : 5140
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
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 15: access
--- extra_init_by_lua
    local syslog = require("apisix.plugins.syslog.init")
    local json = require("apisix.core.json")
    local log = require("apisix.core.log")
    local old_f = syslog.push_entry
    syslog.push_entry = function(conf, ctx, entry)
        assert(entry.vip == "127.0.0.1")
        log.info("push_entry is called with data: ", json.encode(entry))
        return old_f(conf, ctx, entry)
    end
--- request
GET /hello
--- response_body
hello world
--- wait: 0.5
--- no_error_log
[error]
--- error_log
push_entry is called with data



=== TEST 16: check log
--- exec
tail -n 1 ci/pod/vector/syslog-tcp.log
--- response_body eval
qr/.*vip.*/



=== TEST 17: test udp mode
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "batch_max_size": 1,
                                "disable": false,
                                "flush_limit": 1,
                                "host" : "127.0.0.1",
                                "port" : 5150,
                                "sock_type": "udp"
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
--- request
GET /t
--- response_body
passed



=== TEST 18: hit
--- request
GET /hello



=== TEST 19: check log
--- exec
tail -n 1 ci/pod/vector/syslog-udp.log
--- response_body eval
qr/.*upstream.*/



=== TEST 20: add plugin with 'include_req_body' setting, collect request log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/syslog', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "batch_max_size": 1,
                                "flush_limit": 1,
                                "host" : "127.0.0.1",
                                "port" : 5140,
                                "include_req_body": true
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
                ngx.say(body)
                return
            end

            ngx.say(body)

            local code, _, body = t("/hello", "POST", "{\"sample_payload\":\"hello\"}")
        }
    }
--- request
GET /t
--- error_log
"body":"{\"sample_payload\":\"hello\"}"



=== TEST 21: add plugin with 'include_resp_body' setting, collect response log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/syslog', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "syslog": {
                                "batch_max_size": 1,
                                "flush_limit": 1,
                                "host" : "127.0.0.1",
                                "port" : 5140,
                                "include_resp_body": true
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
                ngx.say(body)
                return
            end

            ngx.say(body)

            local code, _, body = t("/hello", "POST", "{\"sample_payload\":\"hello\"}")
        }
    }
--- request
GET /t
--- error_log
"body":"hello world\n"
