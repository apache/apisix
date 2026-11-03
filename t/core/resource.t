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

run_tests;

__DATA__

=== TEST 1: get_nodes_ver returns nil when the resource does not exist
--- config
    location /t {
        content_by_lua_block {
            local resource = require("apisix.resource")
            ngx.say(resource.get_nodes_ver("/apisix/upstreams/missing-resource"))
        }
    }
--- request
GET /t
--- response_body
nil
--- error_log
resource not found: missing-resource in /upstreams
--- no_error_log
[error]
[alert]



=== TEST 2: set_nodes_ver_and_nodes does not fail when the resource does not exist
--- config
    location /t {
        content_by_lua_block {
            local resource = require("apisix.resource")
            resource.set_nodes_ver_and_nodes("/apisix/upstreams/missing-resource", 1,
                                             {["127.0.0.1:1980"] = 1})
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_log
resource not found: missing-resource in /upstreams
--- no_error_log
[error]
[alert]
