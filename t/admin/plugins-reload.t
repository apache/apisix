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
no_shuffle();
log_level("info");
workers(2);
master_on();

run_tests;

__DATA__

=== TEST 1: reload plugins
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, _, org_body = t('/apisix/admin/plugins/reload',
                                    ngx.HTTP_PUT)

        ngx.status = code
        ngx.print(org_body)
        ngx.sleep(0.2)
    }
}
--- request
GET /t
--- response_body
done
--- error_log
load plugin times: 1
load plugin times: 1
start to hot reload plugins
start to hot reload plugins
load plugin times: 2
load plugin times: 2
