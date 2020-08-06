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
                 port = 3000,
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
--- no_error_log
[error]



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.syslog")
            local ok, err = plugin.check_schema({
                 host = "127.0.0.1",
                 port = "3000",
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
                            "syslog": {
                                "host" : "127.0.0.1",
                                "port" : 5044
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
                              "syslog": {
                                 "host" : "127.0.0.1",
                                 "port" : 5044
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
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
--- wait: 0.2



=== TEST 6: flush manually
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.syslog")
            local logger_socket = require("resty.logger.socket")
            local logger, err = logger_socket:new({
                    host = "127.0.0.1",
                    port = 5044,
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
--- no_error_log
[error]



=== TEST 7: small flush_limit, instant flush
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
                                "port" : 5044,
                                "flush_limit" : 1,
                                "timeout": 1
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
--- no_error_log
[error]
--- timeout: 5
