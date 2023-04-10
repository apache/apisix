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
            local plugin = require("apisix.plugins.tcp-logger")
            local ok, err = plugin.check_schema({host = "127.0.0.1", port = 3000})
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



=== TEST 2: missing host
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tcp-logger")
            local ok, err = plugin.check_schema({port = 3000})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "host" is required
done



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tcp-logger")
            local ok, err = plugin.check_schema({host= "127.0.0.1", port = 2000, timeout = "10",
            tls = false, tls_options = "tls options"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "timeout" validation failed: wrong type: expected integer, got string
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
                            "tcp-logger": {
                                "host": "127.0.0.1",
                                "port": 5044,
                                "tls": false
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
--- wait: 1



=== TEST 6: error log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tcp-logger": {
                                "host": "312.0.0.1",
                                "port": 2000,
                                "batch_max_size": 1,
                                "max_retry_count": 2,
                                "retry_delay": 0
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

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
        }
    }
--- request
GET /t
--- error_log
failed to connect to TCP server: host[312.0.0.1] port[2000]
[error]
--- wait: 3



=== TEST 7: check plugin configuration updating
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body1 = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tcp-logger": {
                                "host": "127.0.0.1",
                                "port": 5044,
                                "tls": false,
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
                            "tcp-logger": {
                                "host": "127.0.0.1",
                                "port": 5045,
                                "tls": false,
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



=== TEST 8: bad custom log format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/tcp-logger',
                 ngx.HTTP_PUT,
                 [[{
                        "log_format": "'$host' '$time_iso8601'"
                 }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"log_format\" validation failed: wrong type: expected object, got string"}



=== TEST 9: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tcp-logger": {
                                "host": "127.0.0.1",
                                "port": 8125,
                                "tls": false,
                                "batch_max_size": 1,
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
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/plugin_metadata/tcp-logger',
                 ngx.HTTP_PUT,
                 [[{
                        "log_format": {
                            "host": "$host",
                            "@timestamp": "$time_iso8601",
                            "client_ip": "$remote_addr"
                        }
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



=== TEST 10: access
--- stream_conf_enable
--- extra_stream_config
    server {
        listen 8125;
        content_by_lua_block {
            local decode = require("toolkit.json").decode
            ngx.log(ngx.WARN, "the mock backend is hit")

            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "failed to get the request socket: ", err)
                return
            end

            local data, err = sock:receive('*a')

            if not data then
                if err and err ~= "closed" then
                    ngx.log(ngx.ERR, "socket error, returning: ", err)
                end
                return
            end

            data = decode(data)
            assert(data.client_ip == "127.0.0.1")
        }
    }
--- request
GET /hello
--- response_body
hello world
--- wait: 2
--- error_log
the mock backend is hit
--- no_error_log
[error]



=== TEST 11: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tcp-logger": {
                                "host": "127.0.0.1",
                                "port": 8125,
                                "tls": false,
                                "log_format": {
                                    "vip": "$remote_addr"
                                },
                                "batch_max_size": 1,
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



=== TEST 12: access
--- stream_conf_enable
--- extra_stream_config
    server {
        listen 8125;
        content_by_lua_block {
            local decode = require("toolkit.json").decode
            ngx.log(ngx.WARN, "the mock backend is hit")

            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "failed to get the request socket: ", err)
                return
            end

            local data, err = sock:receive('*a')

            if not data then
                if err and err ~= "closed" then
                    ngx.log(ngx.ERR, "socket error, returning: ", err)
                end
                return
            end

            data = decode(data)
            assert(data.vip == "127.0.0.1")
        }
    }
--- request
GET /hello
--- response_body
hello world
--- wait: 2
--- error_log
the mock backend is hit
--- no_error_log
[error]
