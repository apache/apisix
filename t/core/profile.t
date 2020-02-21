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
BEGIN {
    $ENV{APISIX_PROFILE} = "dev";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: set env "APISIX_PROFILE"
--- config
    location /t {
        content_by_lua_block {
            local profile = require("apisix.core.profile")
            profile.apisix_home = "./test/"
            local local_conf_path = profile:yaml_path("config")
            ngx.say(local_conf_path)
        }
    }
--- request
GET /t
--- response_body
./test/conf/config-dev.yaml
