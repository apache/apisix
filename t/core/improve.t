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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: set route(id: 1)
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
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: enable route cache
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local t = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            local improve = require("apisix.core.improve")
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end
        }
    }
--- response_body
true
true
--- grep_error_log eval
qr/hit route cache, key: [^,]+/
--- grep_error_log_out
hit route cache, key: /hello-GET-127.0.0.1-127.0.0.1



=== TEST 3: route has vars, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "vars": [ ["arg_k", "==", "v"] ],
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

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local t = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            local improve = require("apisix.core.improve")
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end
        }
    }
--- response_body
false
false
--- no_error_log
hit route cache, key: /hello-GET-127.0.0.1-127.0.0.1



=== TEST 4: route with prefix match, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello*"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local t = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            local improve = require("apisix.core.improve")
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end
        }
    }
--- response_body
false
false
--- no_error_log
hit route cache, key: /hello1-GET-127.0.0.1-127.0.0.1



=== TEST 5: route has priority, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "priority": 1,
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

            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "priority": 0,
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

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local t = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            local improve = require("apisix.core.improve")
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end
        }
    }
--- response_body
false
false
--- no_error_log
hit route cache, key: /hello-GET-127.0.0.1-127.0.0.1



=== TEST 6: method changed, create different route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local t = {}
            for i = 1, 4 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err
                    if i % 2 == 0 then
                        res, err =httpc:request_uri(uri, { method = "POST" })
                    else
                        res, err =httpc:request_uri(uri)
                    end
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            local improve = require("apisix.core.improve")
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end
        }
    }
--- response_body
true
true
true
true
--- grep_error_log eval
qr/hit route cache, key: [^,]+/
--- grep_error_log_out
hit route cache, key: /hello-GET-127.0.0.1-127.0.0.1
hit route cache, key: /hello-POST-127.0.0.1-127.0.0.1



=== TEST 7: route with plugins, enable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{

                    "plugins": {
                        "limit-count": {
                            "count": 9999,
                            "time_window": 60
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

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local t = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            local improve = require("apisix.core.improve")
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end
        }
    }
--- response_body
true
true
--- grep_error_log eval
qr/hit route cache, key: [^,]+/
--- grep_error_log_out
hit route cache, key: /hello-GET-127.0.0.1-127.0.0.1



=== TEST 8: enable ->disable -> enable -> diable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local improve = require("apisix.core.improve")
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local uri2 = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1?k=v"

            -- round 1: all routes without vars or filter_fun, enable route cache
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
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local threads1 = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(threads1, th)
            end

            for i, th in ipairs(threads1) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end

            -- round 2: routes with vars or filter_fun, disable route cache
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "vars": [ ["arg_k", "==", "v"] ],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello1"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local threads2 = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri2)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(threads2, th)
            end

            for i, th in ipairs(threads2) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end

           -- round 3: delete route with vars, the remaining route
           -- has no vars or filter_fun, enable route cache
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local threads3 = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(threads3, th)
            end

            for i, th in ipairs(threads3) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end

            -- round 4: routes with vars or filter_fun, disable route cache
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "vars": [ ["arg_k", "==", "v"] ],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello1"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local threads4 = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri2)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(threads4, th)
            end

            for i, th in ipairs(threads4) do
                ngx.thread.wait(th)
                ngx.say(improve.enable_route_cache())
            end

            -- clean route 2
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        }
    }
--- response_body
true
true
false
false
true
true
false
false
--- grep_error_log eval
qr/hit route cache, key: [^,]+/
--- grep_error_log_out
hit route cache, key: /hello-GET-127.0.0.1-127.0.0.1
hit route cache, key: /hello-GET-127.0.0.1-127.0.0.1
--- no_error_log
hit route cache, key: /hello1-GET-127.0.0.1-127.0.0.1
