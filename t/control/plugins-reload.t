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

our $yaml_config = <<_EOC_;
apisix:
  enable_control: true
  node_listen: 1984
_EOC_

run_tests();

__DATA__

=== TEST 1: test plugins-reload
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local code, body, res = t.test('/v1/plugins_reload',
                ngx.HTTP_POST)
            ngx.say(res)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
done
