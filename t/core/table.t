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
            local core = require("apisix.core")
            local t = {"first"}
            core.table.insert_tail(t, 'a', 1, true)

            ngx.say("encode: ", core.json.encode(t))

            core.table.set(t, 'a', 1, true)
            ngx.say("encode: ", core.json.encode(t))
        }
    }
--- request
GET /t
--- response_body
encode: ["first","a",1,true]
encode: ["a",1,true,true]
--- no_error_log
[error]



=== TEST 2: readonly
--- config
    location /t {
        content_by_lua_block {
            local json = require("cjson.safe")
            local core = require("apisix.core")
            local t = {
                a ="a",
                b = {
                    c = "c"
                }
            }

            t.b.d = "d"
            t = core.table.read_only(t)

            local ok, err = pcall(function() t.a = "new_val" end)
            ngx.say("ok: ", ok, " err: ", err)
            local ok, err = pcall(function() t.a_new = "new_val" end)
            ngx.say("ok: ", ok, " err: ", err)
            local ok, err = pcall(function() t.b.c = "new_val" end)
            ngx.say("ok: ", ok, " err: ", err)
            local ok, err = pcall(function() t.b.c_new = "new_val" end)
            ngx.say("ok: ", ok, " err: ", err)

            ngx.say("t.a: ", t.a)
            ngx.say("t.b.c: ", t.b.c)
            ngx.say("json: ", tostring(t))
        }
    }
--- request
GET /t
--- response_body
ok: false err: content_by_lua(nginx.conf:143):14: attempt to update a read-only table
ok: false err: content_by_lua(nginx.conf:143):16: attempt to update a read-only table
ok: false err: content_by_lua(nginx.conf:143):18: attempt to update a read-only table
ok: false err: content_by_lua(nginx.conf:143):20: attempt to update a read-only table
t.a: a
t.b.c: c
json: {"a":"a","b":{"c":"c","d":"d"}}
--- no_error_log
[error]
