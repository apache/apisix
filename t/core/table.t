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
            local t = {"first"}
            core.table.insert_tail(t, 'a', 1, true)

            ngx.say("encode: ", require("toolkit.json").encode(t))

            core.table.set(t, 'a', 1, true)
            ngx.say("encode: ", require("toolkit.json").encode(t))
        }
    }
--- request
GET /t
--- response_body
encode: ["first","a",1,true]
encode: ["a",1,true,true]
--- no_error_log
[error]



=== TEST 2: deepcopy
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local deepcopy = core.table.deepcopy
            local cases = {
                {t = {1, 2, a = {2, 3}}},
                {t = {{a = b}, 2, true}},
                {t = {{a = b}, {{a = c}, {}, 1}, true}},
            }
            for _, case in ipairs(cases) do
                local t = case.t
                local actual = core.json.encode(deepcopy(t))
                local expect = core.json.encode(t)
                if actual ~= expect then
                    ngx.say("expect ", expect, ", actual ", actual)
                    return
                end
            end
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 3: try_read_attr
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local try_read_attr = core.table.try_read_attr

            local t = {level1 = {level2 = "value"}}

            local v = try_read_attr(t, "level1", "level2")
            ngx.say(v)

            local v2 = try_read_attr(t, "level1", "level3")
            ngx.say(v2)
        }
    }
--- request
GET /t
--- response_body
value
nil
--- no_error_log
[error]



=== TEST 4: set_eq
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local cases = {
                {expect = true, a = {}, b = {}},
                {expect = true, a = {a = 1}, b = {a = 1}},
                {expect = true, a = {a = 1}, b = {a = 2}},
                {expect = false, a = {b = 1}, b = {a = 1}},
                {expect = false, a = {a = 1, b = 1}, b = {a = 1}},
                {expect = false, a = {a = 1}, b = {a = 1, b = 2}},
            }
            for _, t in ipairs(cases) do
                local actual = core.table.set_eq(t.a, t.b)
                local expect = t.expect
                if actual ~= expect then
                    ngx.say("expect ", expect, ", actual ", actual)
                    return
                end
            end
            ngx.say("ok")
        }
    }
--- response_body
ok
--- request
GET /t
--- no_error_log
[error]



=== TEST 5: deep_eq
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local cases = {
                {expect = true, a = {}, b = {}},
                {expect = true, a = nil, b = nil},
                {expect = false, a = nil, b = {}},
                {expect = false, a = {}, b = nil},
                {expect = true, a = {a = {b = 1}}, b = {a = {b = 1}}},
                {expect = false, a = {a = {b = 1}}, b = {a = {b = 1, c = 2}}},
                {expect = false, a = {a = {b = 1}}, b = {a = {b = 2}}},
                {expect = true, a = {{a = {b = 1}}}, b = {{a = {b = 1}}}},
            }
            for _, t in ipairs(cases) do
                local actual = core.table.deep_eq(t.a, t.b)
                local expect = t.expect
                if actual ~= expect then
                    ngx.say("expect ", expect, ", actual ", actual)
                    return
                end
            end
            ngx.say("ok")
        }
    }
--- response_body
ok
--- request
GET /t
--- no_error_log
[error]
