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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: keys keep the original order; new keys follow, sorted
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local json_order = require("apisix.utils.json-order")
            local raw = [[{"zeta":1,"alpha":{"y":true,"x":false},"mid":[{"b":1,"a":2}]}]]
            local body = core.json.decode(raw)
            body.mid[1].c = 3
            body.new2, body.new1 = 0, 0
            ngx.say(json_order.encode(body, json_order.shape(raw)))
        }
    }
--- response_body
{"zeta":1,"alpha":{"y":true,"x":false},"mid":[{"b":1,"a":2,"c":3}],"new1":0,"new2":0}



=== TEST 2: an empty array stays an array, an empty object an object, built in Lua too
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local json_order = require("apisix.utils.json-order")
            local raw = [[{"stop":[],"meta":{},"schema":{"required":[],"properties":{}}}]]
            ngx.say(json_order.encode(core.json.decode(raw), json_order.shape(raw)))
            -- a table built in Lua has no array marker: the shape says it was []
            ngx.say(json_order.encode({stop = {}, meta = {}}, json_order.shape(raw)))
        }
    }
--- response_body
{"stop":[],"meta":{},"schema":{"required":[],"properties":{}}}
{"stop":[],"meta":{}}



=== TEST 3: escaped keys, strings, numbers and null round-trip
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local json_order = require("apisix.utils.json-order")
            local raw = [[{"\u00e9":1,"q\"":"a\"b\\c\n\u0001/é","n":-1.5,"f":0.30000000000000004,]]
                .. [["big":9007199254740993,"z":null,"t":true}]]
            ngx.say(json_order.encode(core.json.decode(raw), json_order.shape(raw)))
        }
    }
--- response_body
{"é":1,"q\"":"a\"b\\c\n\u0001/é","n":-1.5,"f":0.30000000000000004,"big":9007199254740992,"z":null,"t":true}



=== TEST 4: no shape (or invalid JSON) sorts every object, deterministically
--- config
    location /t {
        content_by_lua_block {
            local json_order = require("apisix.utils.json-order")
            ngx.say(tostring(json_order.shape("{")), " ", tostring(json_order.shape("[1] x")),
                    " ", tostring(json_order.shape("3")))
            ngx.say(json_order.encode({b = 1, a = {d = 1, c = 2}}, json_order.shape("{")))
        }
    }
--- response_body
nil nil nil
{"a":{"c":2,"d":1},"b":1}



=== TEST 5: a table moved to another path keeps the order of where it came from
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local json_order = require("apisix.utils.json-order")
            local raw = [[{"tools":[{"function":{"parameters":{"b":1,"a":1}}}]}]]
            local body = core.json.decode(raw)
            local params = body.tools[1]["function"].parameters
            local moved = {toolSpec = {inputSchema = {json = params}}}
            local shape = json_order.shape(raw)
            local shapes = {[params] = json_order.child(shape, "tools", 1, "function", "parameters")}
            ngx.say(json_order.encode(moved, nil, shapes))
        }
    }
--- response_body
{"toolSpec":{"inputSchema":{"json":{"b":1,"a":1}}}}



=== TEST 6: what cannot be JSON is an error
--- config
    location /t {
        content_by_lua_block {
            local json_order = require("apisix.utils.json-order")
            for _, bad in ipairs({{[1] = 1, a = 2}, {f = print}, {n = 0 / 0}}) do
                local out, err = json_order.encode(bad)
                ngx.say(tostring(out), " ", err and "error" or "no error")
            end
        }
    }
--- response_body
nil error
nil error
nil error
