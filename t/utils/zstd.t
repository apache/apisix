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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: available() reports whether libzstd is usable
--- config
    location /t {
        content_by_lua_block {
            local zstd = require("apisix.utils.zstd")
            ngx.say("type: ", type(zstd.available()))
        }
    }
--- response_body
type: boolean



=== TEST 2: reject invalid arguments
--- config
    location /t {
        content_by_lua_block {
            local zstd = require("apisix.utils.zstd")

            local _, err = zstd.compress(123)
            ngx.say("data: ", err)

            _, err = zstd.compress("hello", "fastest")
            ngx.say("level: ", err)
        }
    }
--- response_body
data: invalid data type: number
level: invalid compression level



=== TEST 3: compress data into a zstd frame
--- config
    location /t {
        content_by_lua_block {
            local zstd = require("apisix.utils.zstd")

            local data = string.rep("hello apisix tencent-cloud-cls ", 1000)
            local compressed, err = zstd.compress(data)
            if not compressed then
                ngx.say("failed to compress: ", err)
                return
            end

            -- the zstd frame magic number is 0xFD2FB528, stored in little endian
            ngx.say("magic: ", string.format("%02x%02x%02x%02x",
                                             compressed:byte(1), compressed:byte(2),
                                             compressed:byte(3), compressed:byte(4)))
            ngx.say("smaller: ", #compressed < #data)
        }
    }
--- response_body
magic: 28b52ffd
smaller: true
--- skip_eval
3: system("ldconfig -p 2>/dev/null | grep -q libzstd")



=== TEST 4: compress with the given level
--- config
    location /t {
        content_by_lua_block {
            local zstd = require("apisix.utils.zstd")

            local data = string.rep("{\"key\":\"value\"},", 2000)
            for _, level in ipairs({1, 3, 9}) do
                local compressed, err = zstd.compress(data, level)
                if not compressed then
                    ngx.say("failed to compress with level ", level, ": ", err)
                    return
                end
                ngx.say("level ", level, ": ", #compressed < #data)
            end
        }
    }
--- response_body
level 1: true
level 3: true
level 9: true
--- skip_eval
3: system("ldconfig -p 2>/dev/null | grep -q libzstd")
