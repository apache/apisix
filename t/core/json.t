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
            local json_data = core.json.encode({test="test"})

            ngx.say("encode: ", json_data)

            local data = core.json.decode(json_data)
            ngx.say("data: ", data.test)
        }
    }
--- request
GET /t
--- response_body
encode: {"test":"test"}
data: test
--- no_error_log
[error]



=== TEST 2: delay_encode
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local data1 = core.json.delay_encode({test="test1"})
            local data2 = core.json.delay_encode({test="test2"})

            ngx.say("delay encode: ", data1 == data2)
            ngx.say("data1 type: ", type(data1))
            ngx.log(ngx.ERR, "data1 val: ", data1)
            ngx.log(ngx.ERR, "data2 val: ", data2)
        }
    }
--- request
GET /t
--- response_body
delay encode: true
data1 type: table
--- error_log
data1 val: {"test":"test2"}
data2 val: {"test":"test2"}



=== TEST 3: encode with force argument
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local data = core.json.encode({test="test", fun = function() end}, true)

            ngx.say("encode: ", data)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/\{"test":"test","fun":"function: 0x[0-9a-f]+"}/
--- no_error_log
[error]



=== TEST 4: encode, include `cdata` type
--- config
    location /t {
        content_by_lua_block {
            local ffi = require "ffi"
            local charpp = ffi.new("char *[1]")

            local core = require("apisix.core")
            local json_data = core.json.encode({test=charpp}, true)
            ngx.say("encode: ", json_data)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/encode: \{"test":"cdata\<char \*\[1\]>: 0x[0-9a-f]+"\}/
--- no_error_log
[error]



=== TEST 5: excessive nesting
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local a = {}
            local b = {}
            a.b = b
            b.a = a

            local json_data = core.json.encode(a, true)
            ngx.say("encode: ", json_data)
        }
    }
--- request
GET /t
--- response_body eval
qr/\{"b":\{"a":\{"b":"table: 0x[\w]+"\}\}\}/
--- no_error_log
[error]
