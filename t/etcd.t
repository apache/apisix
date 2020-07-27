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
log_level('info');
no_long_string();
no_root_location();

run_tests;

__DATA__


=== TEST 1: set invalid service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/test_key", "test")

            if res.status >= 300 then
                ngx.status = code
                return ngx.say(res.body)
            end

            ngx.print(core.json.encode(res.body))
            ngx.sleep(1)
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr{invalid item data of \[/apisix/test\], val: 123xxxx, it shoud be a object}
--- response_body_like eval
qr/"value":"123xxxx"/
