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

=== TEST 1: find
--- config
    location /t {
        content_by_lua_block {
            local encode = require "toolkit.json".encode 
            local str = require("apisix.core.string")
            local cases = {
                {"xx", "", true},
                {"xx", "x", true},
                {"", "x", false},
                {"", "", true},
                {"", 0, false},
                {0, "x", false},
                {"a[", "[", true},

                {"[a", "[", false, 2},
                {"[a", "[", false, 3},
                {"[a", "[", true, 1},
            }
            for _, case in ipairs(cases) do
                local ok, idx = pcall(str.find, case[1], case[2], case[4])
                if not ok then
                    if case[3] == true then
                        ngx.log(ngx.ERR, "unexpected error: ", idx,
                                " ", encode(case))
                    end
                else
                    if case[3] ~= (idx ~= nil) then
                        ngx.log(ngx.ERR, "unexpected res: ", idx,
                                " ", encode(case))
                    end
                end
            end
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 2: prefix
--- config
    location /t {
        content_by_lua_block {
            local encode = require "toolkit.json".encode 
            local str = require("apisix.core.string")
            local cases = {
                {"xx", "", true},
                {"xx", "x", true},
                {"", "x", false},
                {"", "", true},
                {"", 0, false},
                {0, "x", false},
                {"a[", "[", false},
                {"[a", "[", true},
                {"[a", "[b", false},
            }
            for _, case in ipairs(cases) do
                local ok, res = pcall(str.has_prefix, case[1], case[2])
                if not ok then
                    if case[3] == true then
                        ngx.log(ngx.ERR, "unexpected error: ", res,
                                " ", encode(case))
                    end
                else
                    if case[3] ~= res then
                        ngx.log(ngx.ERR, "unexpected res: ", res,
                                " ", encode(case))
                    end
                end
            end
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 3: suffix
--- config
    location /t {
        content_by_lua_block {
            local encode = require "toolkit.json".encode 
            local str = require("apisix.core.string")
            local cases = {
                {"xx", "", true},
                {"xx", "x", true},
                {"", "x", false},
                {"", "", true},
                {"", 0, false},
                {0, "x", false},
                {"a[", "[", true},
                {"[a", "[", false},
                {"[a", "[b", false},
            }
            for _, case in ipairs(cases) do
                local ok, res = pcall(str.has_suffix, case[1], case[2])
                if not ok then
                    if case[3] == true then
                        ngx.log(ngx.ERR, "unexpected error: ", res,
                                " ", encode(case))
                    end
                else
                    if case[3] ~= res then
                        ngx.log(ngx.ERR, "unexpected res: ", res,
                                " ", encode(case))
                    end
                end
            end
        }
    }
--- request
GET /t
--- no_error_log
[error]
