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

run_tests;

__DATA__

=== TEST 1: test gzip compression levels
--- config
    location /t {
        content_by_lua_block {
            -- generate a big string of 4MB
            local big_raw = string.rep("h", 1024 * 1024 * 4)
            ngx.log(ngx.NOTICE, "original size: ", #big_raw)

            local gzip = require("apisix.utils.gzip")
            local data_l1, err = gzip.deflate_gzip(big_raw, nil, { level = 1 })
            assert(err == nil)
            local data_l9, err = gzip.deflate_gzip(big_raw, nil, { level = 9 })
            assert(err == nil)

            assert(#data_l9 < #data_l1, "expected level 9: " .. #data_l9 .. " < level 1: " .. #data_l1)
        }
    }
--- request
GET /t
--- error_code: 200



=== TEST 2: a concatenated stream inflates every member
--- config
    location /t {
        content_by_lua_block {
            local gzip = require("apisix.utils.gzip")
            local payload = gzip.deflate_gzip([[{"name":]])
                            .. gzip.deflate_gzip([["doggie"}]])

            local out, err = gzip.inflate_gzip(payload)
            ngx.say("err: ", err)
            ngx.say("out: ", out)
        }
    }
--- request
GET /t
--- response_body
err: nil
out: {"name":"doggie"}



=== TEST 3: max_output bounds every member together
--- config
    location /t {
        content_by_lua_block {
            local gzip = require("apisix.utils.gzip")
            local parts = {}
            for _ = 1, 20 do
                parts[#parts + 1] = gzip.deflate_gzip(string.rep("d", 100))
            end
            local payload = table.concat(parts)

            -- every member inflates to 100 bytes, their total is 2000
            local out, err, exceeded = gzip.inflate_gzip(payload, nil, nil, 128)
            ngx.say("out: ", out)
            ngx.say("err: ", err)
            ngx.say("exceeded: ", exceeded)

            local all = gzip.inflate_gzip(payload, nil, nil, 4096)
            ngx.say("under a 4096 cap: ", #all, " bytes")
        }
    }
--- request
GET /t
--- response_body
out: nil
err: inflated data is greater than the maximum size 128 allowed
exceeded: true
under a 4096 cap: 2000 bytes



=== TEST 4: a corrupt later member is rejected
--- config
    location /t {
        content_by_lua_block {
            local gzip = require("apisix.utils.gzip")
            local payload = gzip.deflate_gzip([[{"a":1}]]) .. "not a gzip member"

            local out, err = gzip.inflate_gzip(payload)
            ngx.say("out: ", out)
            ngx.say("err: ", err)
        }
    }
--- request
GET /t
--- response_body
out: nil
err: inflate gzip err: INFLATE: data error



=== TEST 5: bytes trailing the last member are rejected
--- config
    location /t {
        content_by_lua_block {
            local gzip = require("apisix.utils.gzip")
            local payload = gzip.deflate_gzip([[{"a":1}]]) .. "\0"

            local out, err = gzip.inflate_gzip(payload)
            ngx.say("out: ", out)
            ngx.say("err: ", err)
        }
    }
--- request
GET /t
--- response_body
out: nil
err: inflate gzip err: INFLATE: Data error, no input bytes



=== TEST 6: an empty payload is still an error
--- config
    location /t {
        content_by_lua_block {
            local gzip = require("apisix.utils.gzip")
            local out, err = gzip.inflate_gzip("")
            ngx.say("out: ", out)
            ngx.say("err: ", err)
        }
    }
--- request
GET /t
--- response_body
out: nil
err: inflate gzip err: INFLATE: Data error, no input bytes
