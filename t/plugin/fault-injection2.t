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
no_root_location();
no_shuffle();
master_on();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: vars rule with ! (set)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [=[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                        "http_status": 403,
                                        "body": "Fault Injection!\n",
                                        "vars": [
                                            [
                                                "!AND",
                                                ["arg_name","==","jack"],
                                                ["arg_age","!","<",18]
                                            ]
                                        ]
                                    }
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
                           },
                           "uri": "/hello"
                   }]=]
                   )
               if code >= 300 then
                   ngx.status = code
               end
               ngx.say(body)
           }
       }
--- response_body
passed



=== TEST 2: vars rule with ! (hit)
--- request
GET /hello?name=jack&age=17
--- error_code: 403
--- response_body
Fault Injection!



=== TEST 3: vars rule with ! (miss)
--- request
GET /hello?name=jack&age=18
--- response_body
hello world
