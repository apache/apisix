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

=== TEST 1: exit with string
--- config
    location = /t {
        access_by_lua_block {
            local core = require("apisix.core")
            core.response.exit(201, "done\n")
        }
    }
--- request
GET /t
--- error_code: 201
--- response_body
done
--- no_error_log
[error]



=== TEST 2: exit with table
--- config
    location = /t {
        access_by_lua_block {
            local core = require("apisix.core")
            core.response.exit(201, {a = "a"})
        }
    }
--- request
GET /t
--- error_code: 201
--- response_body
{"a":"a"}
--- no_error_log
[error]



=== TEST 3: multiple response headers
--- config
    location = /t {
        access_by_lua_block {
            local core = require("apisix.core")
            core.response.set_header("aaa", "bbb", "ccc", "ddd")
            core.response.exit(200, "done\n")
        }
    }
--- request
GET /t
--- response_body
done
--- response_headers
aaa: bbb
ccc: ddd
--- no_error_log
[error]



=== TEST 4: multiple response headers by table
--- config
    location = /t {
        access_by_lua_block {
            local core = require("apisix.core")
            core.response.set_header({aaa = "bbb", ccc = "ddd"})
            core.response.exit(200, "done\n")
        }
    }
--- request
GET /t
--- response_body
done
--- response_headers
aaa: bbb
ccc: ddd
--- no_error_log
[error]



=== TEST 5: multiple response headers (add)
--- config
    location = /t {
        access_by_lua_block {
            local core = require("apisix.core")
            core.response.add_header("aaa", "bbb", "aaa", "bbb")
            core.response.exit(200, "done\n")
        }
    }
--- request
GET /t
--- response_body
done
--- response_headers
aaa: bbb, bbb
--- no_error_log
[error]



=== TEST 6: multiple response headers by table (add)
--- config
    location = /t {
        access_by_lua_block {
            local core = require("apisix.core")
            core.response.set_header({aaa = "bbb"})
            core.response.add_header({aaa = "bbb", ccc = "ddd"})
            core.response.exit(200, "done\n")
        }
    }
--- request
GET /t
--- response_body
done
--- response_headers
aaa: bbb, bbb
ccc: ddd
--- no_error_log
[error]
