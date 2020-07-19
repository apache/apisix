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
no_root_location();

run_tests;

__DATA__

=== TEST 1: Set and Get a value pass with authentication
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local key = "/test_key"
            local val = "test_value"
            core.etcd.set(key, val)
            local res, err = core.etcd.get(key)
            local inspect = require("inspect")
            ngx.say(inspect(res))
            ngx.say(res.body.node.value)
            core.etcd.delete(val)
        }
    }
--- request
GET /t
--- response_body
test_value
--- no_error_log
[error]