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

workers(4);
log_level('info');
repeat_each(1);
no_long_string();
no_root_location();

run_tests();

__DATA__

=== TEST 1: generate different random number in different worker process
--- stream_enable
--- config
    location /test {
        content_by_lua_block {
            ngx.sleep(0.3)
            local log_file = ngx.config.prefix() .. "logs/error.log"
            local file = io.open(log_file, "r")
            local log = file:read("*a")

            local it, err = ngx.re.gmatch(log, [[random stream test in \[1, 10000\]: (\d+)]], "jom")
            if not it then
                ngx.log(ngx.ERR, "failed to gmatch: ", err)
                return
            end

            local random_nums = {}
            while true do
                local m, err = it()
                if err then
                    ngx.log(ngx.ERR, "error: ", err)
                    return
                end

                if not m then
                    break
                end

                -- found a match
                table.insert(random_nums, m[1])
            end

            for i = 2, #random_nums do
                local pre = random_nums[i - 1]
                local cur = random_nums[i]
                ngx.say("random[", i - 1, "] == random[", i, "]: ", pre == cur)
                if not pre == cur then
                    ngx.say("random info in log: ", table.concat(random_nums, ", "))
                    break
                end
            end
        }
    }
--- request
GET /test
--- response_body
random[1] == random[2]: false
random[2] == random[3]: false
random[3] == random[4]: false
random[4] == random[5]: false
--- no_error_log
[error]
