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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: two-space indent with a space after the colon
--- config
    location /t {
        content_by_lua_block {
            local jp = require("apisix.plugins.openapi-to-mcp.json_pretty")
            ngx.say(jp.encode({ a = 1 }))
        }
    }
--- response_body
{
  "a": 1
}



=== TEST 2: empty containers stay on one line
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local jp = require("apisix.plugins.openapi-to-mcp.json_pretty")
            local arr = setmetatable({}, core.json.array_mt)
            -- one key per object: a multi-key Lua table has no stable
            -- serialisation order, which makes the assertion flaky
            ngx.say(jp.encode({ headers = {} }))
            ngx.say(jp.encode({ items = arr }))
        }
    }
--- response_body
{
  "headers": {}
}
{
  "items": []
}



=== TEST 3: nesting increases the indent
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local jp = require("apisix.plugins.openapi-to-mcp.json_pretty")
            local arr = setmetatable({ 1, 2 }, core.json.array_mt)
            ngx.say(jp.encode({ outer = { inner = arr } }))
        }
    }
--- response_body
{
  "outer": {
    "inner": [
      1,
      2
    ]
  }
}



=== TEST 4: braces and commas inside strings are left alone
--- config
    location /t {
        content_by_lua_block {
            local jp = require("apisix.plugins.openapi-to-mcp.json_pretty")
            ngx.say(jp.encode({ s = 'a{b},c"d' }))
        }
    }
--- response_body
{
  "s": "a{b},c\"d"
}
