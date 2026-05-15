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

log_level('debug');
worker_connections(1024);
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: wrong type
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({include_in_response = "bad_type"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "include_in_response" validation failed: wrong type: expected boolean, got string
done



=== TEST 3: add plugin with include_in_response true (default true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: check for request id in response header (default header name)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["X-Request-Id"] then
                ngx.say("request header present")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
request header present



=== TEST 5: check for unique id
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = {}
            local ids = {}
            local found_dup = false
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function()
                    local httpc = http.new()
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
                    local res, err = httpc:request_uri(uri,
                        {
                            method = "GET",
                            headers = {
                                ["Content-Type"] = "application/json",
                            }
                        }
                    )
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end

                    local id = res.headers["X-Request-Id"]
                    if not id then
                        return -- ignore if the data is not synced yet.
                    end

                    if ids[id] == true then
                        found_dup = true
                        return
                    end
                    ids[id] = true
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end

            if found_dup then
                ngx.say("ids not unique")
            else
                ngx.say("true")
            end
        }
    }
--- wait: 5
--- response_body
true



=== TEST 6: add plugin with custom header name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "header_name": "Custom-Header-Name"
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: check for request id in response header (custom header name)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["Custom-Header-Name"] then
                ngx.say("request header present")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
request header present



=== TEST 8: add plugin with include_in_response false (default true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "include_in_response": false
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: check for request id is not present in the response header
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if not res.headers["X-Request-Id"] then
                ngx.say("request header not present")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
request header not present



=== TEST 10: add plugin with custom header name in global rule and add plugin with default header name in specific route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                     [[{
                        "plugins": {
                            "request-id": {
                                "header_name":"Custom-Header-Name"
                            }
                        }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "request-id": {
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
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: check for multiple request-ids in the response header are different
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["X-Request-Id"] ~= res.headers["Custom-Header-Name"] then
                ngx.say("X-Request-Id and Custom-Header-Name are different")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
X-Request-Id and Custom-Header-Name are different



=== TEST 12: wrong algorithm type
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({algorithm = "bad_algorithm"})
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "algorithm" validation failed: matches none of the enum values
done



=== TEST 13: add plugin with include_in_response true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "include_in_response": true
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: echo back the client's header if given
--- request
GET /opentracing
--- more_headers
X-Request-ID: 123
--- response_headers
X-Request-ID: 123



=== TEST 15: add plugin with algorithm nanoid (default uuid)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local v = {}
            local ids = {}
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "algorithm": "nanoid"
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
                ngx.say("algorithm nanoid is error")
            end
            local found_dup = false
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function()
                    local httpc = http.new()
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
                    local res, err = httpc:request_uri(uri,
                        {
                            method = "GET",
                            headers = {
                                ["Content-Type"] = "application/json",
                            }
                        }
                    )
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                    local id = res.headers["X-Request-Id"]
                    if not id then
                        return -- ignore if the data is not synced yet.
                    end
                    if ids[id] == true then
                        found_dup = true
                        return
                    end
                    ids[id] = true
                end, i))
                table.insert(v, th)
            end
            for i, th in ipairs(v) do
                ngx.thread.wait(th)
            end
            if found_dup then
                ngx.say("ids not unique")
            else
                ngx.say("true")
            end
        }
    }
--- wait: 5
--- response_body
true



=== TEST 16: check for request id in response header when request id is empty in request
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["X-Request-Id"] = ""
                    }
                })

            if res.headers["X-Request-Id"] and res.headers["X-Request-Id"] ~= "" then
                ngx.say("request header present and is not empty")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
request header present and is not empty



=== TEST 17: sanity check - algorithm uuidv7 schema valid
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({
                algorithm = "uuidv7"
            })
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 18: sanity check - algorithm invalid value rejected
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({
                algorithm = "uuidv5"
            })
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body_like
property "algorithm" validation failed: matches none of the enum values



=== TEST 19: add plugin with algorithm uuidv7
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "algorithm": "uuidv7"
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 20: uuid v7 has correct format (version=7, variant=8-b)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say("failed to request: ", err)
                return
            end

            local id = res.headers["X-Request-Id"]
            if not id then
                ngx.say("header not found")
                return
            end

            if not string.match(id, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
                ngx.say("format invalid: ", id)
                return
            end

            if string.sub(id, 15, 15) ~= "7" then
                ngx.say("version wrong, expected 7, got: ", string.sub(id, 15, 15), " in: ", id)
                return
            end

            local variant = string.sub(id, 20, 20)
            if variant ~= "8" and variant ~= "9" and variant ~= "a" and variant ~= "b" then
                ngx.say("variant wrong, got: ", variant, " in: ", id)
                return
            end

            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 21: uuid v7 uniqueness (180 concurrent requests)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = {}
            local ids = {}
            local found_dup = false
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function()
                    local httpc = http.new()
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
                    local res, err = httpc:request_uri(uri, {method = "GET"})
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                    local id = res.headers["X-Request-Id"]
                    if not id then return end
                    if ids[id] then
                        found_dup = true
                        return
                    end
                    ids[id] = true
                end, i))
                table.insert(t, th)
            end
            for _, th in ipairs(t) do
                ngx.thread.wait(th)
            end
            if found_dup then
                ngx.say("duplicate found")
            else
                ngx.say("true")
            end
        }
    }
--- wait: 5
--- response_body
true



=== TEST 22: uuid v7 time ordering (sequential UUIDs are lexicographically monotone)
--- config
    location /t {
        content_by_lua_block {
            local utils = require("apisix.core.utils")
            local prev = utils.generate_uuid_v7()
            local ok = true
            for i = 1, 20 do
                local cur = utils.generate_uuid_v7()
                if cur <= prev then
                    ok = false
                    ngx.say("not monotone: prev=", prev, " cur=", cur)
                    return
                end
                prev = cur
            end
            if ok then
                ngx.say("ok")
            end
        }
    }
--- response_body
ok



=== TEST 23: algorithm uuid (default) generates uuid v4
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"

            t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "algorithm": "uuid"
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

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say("failed: ", err)
                return
            end

            local id = res.headers["X-Request-Id"]
            if not id then
                ngx.say("header not found")
                return
            end

            local ver = string.sub(id, 15, 15)
            if ver ~= "4" then
                ngx.say("expected v4, got version: ", ver)
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 24: uuid v7 timestamp prefix is non-zero (48-bit ts encoded correctly)
--- config
    location /t {
        content_by_lua_block {
            local utils = require("apisix.core.utils")
            local id = utils.generate_uuid_v7()
            local seg1 = string.sub(id, 1, 8)
            if string.sub(seg1, 1, 4) == "0000" then
                ngx.say("ts truncation detected (first 4 hex are 0000): ", id)
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 25: algorithm uuidv7 with custom header name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"

            t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "algorithm": "uuidv7",
                                "header_name": "X-Trace-Id"
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

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say("failed: ", err)
                return
            end

            local id = res.headers["X-Trace-Id"]
            if not id then
                ngx.say("X-Trace-Id header not found")
                return
            end

            if string.sub(id, 15, 15) ~= "7" then
                ngx.say("version wrong: ", id)
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 26: uuid v7 overflow loop refreshes cached ngx.now time
--- config
    location /t {
        content_by_lua_block {
            local debug = require("debug")
            local utils = require("apisix.core.utils")

            local function set_upvalue(func, name, value)
                for i = 1, 32 do
                    local upname = debug.getupvalue(func, i)
                    if not upname then
                        break
                    end

                    if upname == name then
                        debug.setupvalue(func, i, value)
                        return true
                    end
                end

                return false
            end

            local function get_upvalue(func, name)
                for i = 1, 32 do
                    local upname, upvalue = debug.getupvalue(func, i)
                    if not upname then
                        break
                    end

                    if upname == name then
                        return upvalue
                    end
                end
            end

            local gen = utils.generate_uuid_v7
            local old_last_ms = get_upvalue(gen, "_v7_last_ms")
            local old_seq = get_upvalue(gen, "_v7_seq")
            local old_rand_b = get_upvalue(gen, "_v7_rand_b")
            local old_ngx_now = get_upvalue(gen, "ngx_now")
            local old_ngx_update_time = get_upvalue(gen, "ngx_update_time")

            local fake_now = 1000.100
            local update_calls = 0
            local now_calls = 0

            assert(set_upvalue(gen, "_v7_last_ms", 1000100))
            assert(set_upvalue(gen, "_v7_seq", 0x3ffff))
            assert(set_upvalue(gen, "_v7_rand_b", {1, 2, 3, 4, 5, 6, 7}))
            assert(set_upvalue(gen, "ngx_now", function()
                now_calls = now_calls + 1
                if now_calls > 5 and update_calls == 0 then
                    error("stale cached time")
                end
                return fake_now
            end))
            assert(set_upvalue(gen, "ngx_update_time", function()
                update_calls = update_calls + 1
                fake_now = 1000.101
            end))

            local ok, id = pcall(gen)

            assert(set_upvalue(gen, "_v7_last_ms", old_last_ms))
            assert(set_upvalue(gen, "_v7_seq", old_seq))
            assert(set_upvalue(gen, "_v7_rand_b", old_rand_b))
            assert(set_upvalue(gen, "ngx_now", old_ngx_now))
            assert(set_upvalue(gen, "ngx_update_time", old_ngx_update_time))

            if not ok then
                ngx.say(id)
                return
            end

            if update_calls < 1 then
                ngx.say("ngx.update_time not called")
                return
            end

            if string.sub(id, 15, 15) ~= "7" then
                ngx.say("not uuidv7: ", id)
                return
            end

            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 27: uuid v7 stays monotone when clock moves backwards
--- config
    location /t {
        content_by_lua_block {
            local debug = require("debug")
            local utils = require("apisix.core.utils")

            local function set_upvalue(func, name, value)
                for i = 1, 32 do
                    local upname = debug.getupvalue(func, i)
                    if not upname then
                        break
                    end

                    if upname == name then
                        debug.setupvalue(func, i, value)
                        return true
                    end
                end

                return false
            end

            local function get_upvalue(func, name)
                for i = 1, 32 do
                    local upname, upvalue = debug.getupvalue(func, i)
                    if not upname then
                        break
                    end

                    if upname == name then
                        return upvalue
                    end
                end
            end

            local gen = utils.generate_uuid_v7
            local old_last_ms = get_upvalue(gen, "_v7_last_ms")
            local old_seq = get_upvalue(gen, "_v7_seq")
            local old_rand_b = get_upvalue(gen, "_v7_rand_b")
            local old_ngx_now = get_upvalue(gen, "ngx_now")
            local old_ngx_update_time = get_upvalue(gen, "ngx_update_time")

            local fixed_rand = {1, 2, 3, 4, 5, 6, 7}
            local fixed_last_ms = 1000100

            assert(set_upvalue(gen, "_v7_last_ms", fixed_last_ms))
            assert(set_upvalue(gen, "_v7_seq", 4))
            assert(set_upvalue(gen, "_v7_rand_b", fixed_rand))
            assert(set_upvalue(gen, "ngx_now", function() return 1000.100 end))
            assert(set_upvalue(gen, "ngx_update_time", function() end))
            local expected = gen()

            assert(set_upvalue(gen, "_v7_last_ms", fixed_last_ms))
            assert(set_upvalue(gen, "_v7_seq", 4))
            assert(set_upvalue(gen, "_v7_rand_b", fixed_rand))
            assert(set_upvalue(gen, "ngx_now", function() return 1000.099 end))
            local actual = gen()

            assert(set_upvalue(gen, "_v7_last_ms", old_last_ms))
            assert(set_upvalue(gen, "_v7_seq", old_seq))
            assert(set_upvalue(gen, "_v7_rand_b", old_rand_b))
            assert(set_upvalue(gen, "ngx_now", old_ngx_now))
            assert(set_upvalue(gen, "ngx_update_time", old_ngx_update_time))

            if actual ~= expected then
                ngx.say("rollback changed encoded timestamp: expected=", expected, " actual=", actual)
                return
            end

            ngx.say("ok")
        }
    }
--- response_body
ok
