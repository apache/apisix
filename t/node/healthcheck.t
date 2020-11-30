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

master_on();
repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

run_tests();

__DATA__

=== TEST 1: set route(two healthy upstream nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 2: hit routes (two healthy nodes)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(2) -- wait for sync

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":6,"port":"1981"},{"count":6,"port":"1980"}]
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out
--- timeout: 6



=== TEST 3: set route(two upstream node: one healthy + one unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1970": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 4: hit routes (two upstream node: one healthy + one unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            end

            ngx.sleep(2.5)

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end

                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/unhealthy .* for '.*'/
--- grep_error_log_out
unhealthy TCP increment (1/2) for 'foo.com(127.0.0.1:1970)'
unhealthy TCP increment (2/2) for 'foo.com(127.0.0.1:1970)'
--- timeout: 10



=== TEST 5: chash route (two healthy nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "chash",
                        "nodes": {
                            "127.0.0.1:1981": 1,
                            "127.0.0.1:1980": 1
                        },
                        "key": "remote_addr",
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 6: hit routes (two healthy nodes)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(2) -- wait for sync

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out
--- timeout: 6



=== TEST 7: chash route (upstream nodes: 1 healthy + 8 unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "chash",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1970": 1,
                            "127.0.0.1:1971": 1,
                            "127.0.0.1:1972": 1,
                            "127.0.0.1:1973": 1,
                            "127.0.0.1:1974": 1,
                            "127.0.0.1:1975": 1,
                            "127.0.0.1:1976": 1,
                            "127.0.0.1:1977": 1
                        },
                        "key": "remote_addr",
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 8: hit routes (upstream nodes: 1 healthy + 8 unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            end

            ngx.sleep(2.5)

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end

                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out eval
qr/Connection refused\) while connecting to upstream/
--- timeout: 10



=== TEST 9: chash route (upstream nodes: 2 unhealthy)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{"uri":"/server_port","upstream":{"type":"chash","nodes":{"127.0.0.1:1960":1,"127.0.0.1:1961":1},"key":"remote_addr","retries":3,"checks":{"active":{"http_path":"/status","host":"foo.com","healthy":{"interval":999,"successes":3},"unhealthy":{"interval":999,"http_failures":3}},"passive":{"healthy":{"http_statuses":[200,201],"successes":3},"unhealthy":{"http_statuses":[500],"http_failures":3,"tcp_failures":3}}}}}]]
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
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 10: hit routes (passive + retries)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri,
                    {method = "GET", keepalive = false}
                )
                ngx.say("res: ", res.status, " err: ", err)
            end
        }
    }
--- request
GET /t
--- response_body
res: 502 err: nil
res: 502 err: nil
--- grep_error_log eval
qr{\[error\].*while connecting to upstream.*}
--- grep_error_log_out eval
qr{.*http://127.0.0.1:1960/server_port.*
.*http://127.0.0.1:1960/server_port.*
.*http://127.0.0.1:1961/server_port.*
.*http://127.0.0.1:1961/server_port.*
.*http://127.0.0.1:1961/server_port.*}
--- timeout: 10



=== TEST 11: add new routh with healthcheck attribute
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for i = 1, 3 do
                t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "uri": "/server_port",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "checks": {
                                "active": {
                                    "http_path": "/status",
                                    "host": "foo.com",
                                    "healthy": {
                                        "interval": 1,
                                        "successes": 1
                                    },
                                    "unhealthy": {
                                        "interval": 1,
                                        "http_failures": 2
                                    }
                                }
                            }
                        }
                    }]]
                )

                ngx.sleep(0.1)

                local code, body = t('/server_port', ngx.HTTP_GET)
                ngx.say("code: ", code, " body: ", body)

                code, body = t('/apisix/admin/routes/' .. i, ngx.HTTP_DELETE)
                ngx.say("delete code: ", code)

                ngx.sleep(0.1)
            end
        }
    }
--- request
GET /t
--- response_body
code: 200 body: passed
delete code: 200
code: 200 body: passed
delete code: 200
code: 200 body: passed
delete code: 200
--- no_error_log
[error]



=== TEST 12: add route (test health check config `host` valid)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1988": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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



=== TEST 13: test health check config `host` valid
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})

            ngx.sleep(2)

            ngx.say(res.status)
        }
    }
--- request
GET /t
--- response_body
200
--- grep_error_log eval
qr/^.*?\[warn\].*/
--- grep_error_log_out eval
qr/unhealthy TCP increment.*foo.com/



=== TEST 14: add route (test health check customized `port`)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "port": 1988,
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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



=== TEST 15: test health check customized `port`
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})

            ngx.sleep(2)

            ngx.say(res.status)
        }
    }
--- request
GET /t
--- response_body
200
--- grep_error_log eval
qr/^.*?\[warn\].*/
--- grep_error_log_out eval
qr/unhealthy TCP increment.*foo.com.*127.0.0.1:1988/
--- timeout: 5



=== TEST 16: add route (test health check customized `port` out of minimum range)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "port": 0,
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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
--- response_body_like eval
qr/expected 0 to be greater than 1/
--- error_code chomp
400



=== TEST 17: add route (test health check customized `port` out of maximum range)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "port": 65536,
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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
--- response_body_like eval
qr/expected 65536 to be smaller than 65535/
--- error_code chomp
400
