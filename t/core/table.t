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



=== TEST 6: pick
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
            local cases = {
                {expect = {}, a = {}, b = {priority = true}},
                {expect = {priority = 1}, a = {priority = 1}, b = {priority = true}},
                {expect = {}, a = {priorities = 1}, b = {priority = true}},
                {expect = {priority = 1}, a = {priority = 1, ver = "2"}, b = {priority = true}},
                {expect = {priority = 1, ver = "2"}, a = {priority = 1, ver = "2"}, b = {priority = true, ver = true}},
            }
            for _, t in ipairs(cases) do
                local actual = core.table.pick(t.a, t.b)
                local expect = t.expect
                if not core.table.deep_eq(actual, expect) then
                    ngx.say("expect ", json.encode(expect), ", actual ", json.encode(actual))
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



=== TEST 7: deepcopy should keep metatable
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local deepcopy = core.table.deepcopy
            local t = setmetatable({}, core.json.array_mt)
            local actual = core.json.encode(deepcopy(t))
            local expect = "[]"
            if actual ~= expect then
                ngx.say("expect ", expect, ", actual ", actual)
                return
            end
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok



=== TEST 8: deepcopy copy same table only once
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local tmp = { name = "tmp", priority = 1, enabled = true }
            local origin = { a = { b = tmp }, c = tmp}
            local copy = core.table.deepcopy(origin)
            if not core.table.deep_eq(copy, origin) then
                ngx.say("copy: ", json.encode(expect), ", origin: ", json.encode(actual))
                return
            end
            if copy.a.b ~= copy.c then
                ngx.say("copy.a.b should be the same as copy.c")
                return
            end
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok



=== TEST 9: reference same table
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local deepcopy = core.table.deepcopy
            local tab1 = {name = "tab1"}
            local tab2 = {
                a = tab1,
                b = tab1
            }
            local tab_copied = deepcopy(tab2)

            ngx.say("table copied: ", require("toolkit.json").encode(tab_copied))

            ngx.say("tab1 == tab2.a: ", tab1 == tab2.a)
            ngx.say("tab2.a == tab2.b: ", tab2.a == tab2.b)

            ngx.say("tab_copied.a == tab1: ", tab_copied.a == tab1)
            ngx.say("tab_copied.a == tab_copied.b: ", tab_copied.a == tab_copied.b)
        }
    }
--- request
GET /t
--- response_body
table copied: {"a":{"name":"tab1"},"b":{"name":"tab1"}}
tab1 == tab2.a: true
tab2.a == tab2.b: true
tab_copied.a == tab1: false
tab_copied.a == tab_copied.b: true



=== TEST 10: reference table self(root node)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local deepcopy = core.table.deepcopy
            local tab1 = {name = "tab1"}
            local tab2 = {
                a = tab1,
            }
            tab2.c = tab2

            local tab_copied = deepcopy(tab2)

            ngx.say("tab_copied.a == tab1: ", tab_copied.a == tab_copied.b)
            ngx.say("tab_copied == tab_copied.c: ", tab_copied == tab_copied.c)
        }
    }
--- request
GET /t
--- response_body
tab_copied.a == tab1: false
tab_copied == tab_copied.c: true



=== TEST 11: reference table self(sub node)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local deepcopy = core.table.deepcopy
            local tab_org = {
                a = {
                    a2 = "a2"
                },
            }
            tab_org.b = tab_org.a

            local tab_copied = deepcopy(tab_org)
            ngx.say("table copied: ", require("toolkit.json").encode(tab_copied))
            ngx.say("tab_copied.a == tab_copied.b: ", tab_copied.a == tab_copied.b)
        }
    }
--- request
GET /t
--- response_body
table copied: {"a":{"a2":"a2"},"b":{"a2":"a2"}}
tab_copied.a == tab_copied.b: true



=== TEST 12: shallow copy
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local deepcopy = core.table.deepcopy
            local t1 = {name = "tab1"}
            local t2 = {name = "tab2"}
            local tab = {
                a = {b = {c = t1}},
                x = {y = t2},
            }
            local tab_copied = deepcopy(tab, { shallows = { "self.a.b.c" }})

            ngx.say("table copied: ", require("toolkit.json").encode(tab_copied))

            ngx.say("tab_copied.a.b.c == tab.a.b.c1: ", tab_copied.a.b.c == tab.a.b.c)
            ngx.say("tab_copied.a.b.c == t1: ", tab_copied.a.b.c == t1)
            ngx.say("tab_copied.x.y == tab.x.y: ", tab_copied.x.y == tab.x.y)
            ngx.say("tab_copied.x.y == t2: ", tab_copied.x.y == t2)
        }
    }
--- request
GET /t
--- response_body
table copied: {"a":{"b":{"c":{"name":"tab1"}}},"x":{"y":{"name":"tab2"}}}
tab_copied.a.b.c == tab.a.b.c1: true
tab_copied.a.b.c == t1: true
tab_copied.x.y == tab.x.y: false
tab_copied.x.y == t2: false
