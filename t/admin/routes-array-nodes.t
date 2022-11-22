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

run_tests;

__DATA__

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": [{
                            "host": "127.0.0.1",
                            "port": 8080,
                            "weight": 1
                        }],
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]],
                [[{
                    "value": {
                        "methods": [
                            "GET"
                        ],
                        "uri": "/index.html",
                        "desc": "new route",
                        "upstream": {
                            "nodes": [{
                                "host": "127.0.0.1",
                                "port": 8080,
                                "weight": 1
                            }],
                            "type": "roundrobin"
                        }
                    },
                    "key": "/apisix/routes/1"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: get route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_GET,
                nil,
                [[{
                    "value": {
                        "methods": [
                            "GET"
                        ],
                        "uri": "/index.html",
                        "desc": "new route",
                        "upstream": {
                            "nodes": [{
                                "host": "127.0.0.1",
                                "port": 8080,
                                "weight": 1
                            }],
                            "type": "roundrobin"
                        }
                    },
                    "key": "/apisix/routes/1"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
