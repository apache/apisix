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
