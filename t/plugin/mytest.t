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
no_shuffle();
run_tests;

__DATA__

=== TEST 8: the upstream node is IP and pass_host is `node`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")

            local data = {
                uri = "/uri",
                plugins = {
                    ["traffic-split"] = {
                        rules = {{
                            match = { {
                              vars = { { "arg_name", "==", "jack" } }
                            } },
                            weighted_upstreams = {
                                {
                                    upstream = {
                                        type = "roundrobin",
                                        pass_host = "node",
                                        nodes = {["127.0.0.1:1981"] = 1}
                                    }
                                }
                            }
                        }}
                    }
                },
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                }
            }

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: upstream_host is localhost
--- request
GET /uri?name=jack
--- more_headers
host: 127.0.0.1
--- response_body
uri: /uri
host: localhost
x-real-ip: 127.0.0.1

