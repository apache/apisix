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
no_root_location();

run_tests();

__DATA__

=== TEST 1: set stream route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
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



=== TEST 2: hit route
--- stream_request eval
mmm
--- stream_response
hello world



=== TEST 3: set stream route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.2",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
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



=== TEST 4: not hit route
--- stream_enable
--- stream_response



=== TEST 5: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
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



=== TEST 6: set stream route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "server_port": 1995,
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
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



=== TEST 7: set upstream (id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1995": 1
                    },
                    "type": "roundrobin"
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



=== TEST 8: set stream route (id: 1) which uses upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream_id": "1"
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



=== TEST 9: hit route
--- stream_request eval
mmm
--- stream_response
hello world



=== TEST 10: skip route config tombstone
--- stream_conf_enable
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        t('/apisix/admin/stream_routes/1',
            ngx.HTTP_PUT,
            [[{
                "upstream": {
                    "nodes": {
                        "127.0.0.1:1995": 1
                    },
                    "type": "roundrobin"
                }
            }]]
        )
        t('/apisix/admin/stream_routes/1', ngx.HTTP_DELETE)
        t('/apisix/admin/stream_routes/1',
            ngx.HTTP_PUT,
            [[{
                "upstream": {
                    "nodes": {
                        "127.0.0.1:1995": 1
                    },
                    "type": "roundrobin"
                }
            }]]
        )

        local sock = ngx.socket.tcp()
        local ok, err = sock:connect("127.0.0.1", 1985)
        if not ok then
            ngx.say("failed to connect: ", err)
            return
        end

        assert(sock:send("mmm"))
        local data = assert(sock:receive("*a"))
        ngx.print(data)
    }
}
--- request
GET /t
--- response_body
hello world



=== TEST 11: set stream route (id: 1) which uses upstream_id and remote address with IP CIDR
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1/26",
                    "upstream_id": "1"
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



=== TEST 12: hit route
--- stream_request eval
mmm
--- stream_response
hello world



=== TEST 13: reject bad CIDR
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": ":/8",
                    "upstream_id": "1"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid remote_addr: :/8"}



=== TEST 14: skip upstream http host check in stream subsystem
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1995": 1,
                        "127.0.0.2:1995": 1
                    },
                    "pass_host": "node",
                    "type": "roundrobin"
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



=== TEST 15: hit route
--- stream_request eval
mmm
--- stream_response
hello world



=== TEST 16: reuse ctx and more
--- stream_extra_init_by_lua
    local ctx = require("apisix.core.ctx")
    local tablepool = require("apisix.core").tablepool

    local old_set_vars_meta = ctx.set_vars_meta
    ctx.set_vars_meta = function(...)
        ngx.log(ngx.WARN, "fetch ctx var")
        return old_set_vars_meta(...)
    end

    local old_release_vars = ctx.release_vars
    ctx.release_vars = function(...)
        ngx.log(ngx.WARN, "release ctx var")
        return old_release_vars(...)
    end

    local old_fetch = tablepool.fetch
    tablepool.fetch = function(name, ...)
        ngx.log(ngx.WARN, "fetch table ", name)
        return old_fetch(name, ...)
    end

    local old_release = tablepool.release
    tablepool.release = function(name, ...)
        ngx.log(ngx.WARN, "release table ", name)
        return old_release(name, ...)
    end
--- stream_request eval
mmm
--- stream_response
hello world
--- grep_error_log eval
qr/(fetch|release) (ctx var|table \w+)/
--- grep_error_log_out
fetch table api_ctx
fetch ctx var
fetch table ctx_var
fetch table plugins
release ctx var
release table ctx_var
release table plugins
release table api_ctx
