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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local function job()
                core.log.warn("job enter")
                ngx.sleep(0.5)
                core.log.warn("job exit")
            end

            local ok = core.timer.new("test job", job,
                {each_ttl = 2, check_interval = 0.1})
            ngx.say("create timer: ", type(ok))
            ngx.sleep(3)
        }
    }
--- request
GET /t
--- response_body
create timer: table
--- grep_error_log eval
qr/job (enter|exit)/
--- grep_error_log_out eval
qr/(job enter\njob exit)+/
--- timeout: 5
