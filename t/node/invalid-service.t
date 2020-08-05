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
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set invalid service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/services/1", [[mexxxxxxxxxxxxxxx]])

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
qr{invalid item data of \[/apisix/services/1\], val: mexxxxxxxxxxxxxxx, it shoud be a object}
--- response_body_like eval
qr/"value":"mexxxxxxxxxxxxxxx"/



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"failed to match any routes"}
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr{invalid item data of \[/apisix/services/1\], val: mexxxxxxxxxxxxxxx, it shoud be a object}



=== TEST 3: set valid service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/services/1", core.json.decode([[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                }]]))

            if res.status >= 300 then
                res.status = code
            end

            ngx.print(core.json.encode(res.body))
        }
    }
--- request
GET /t
--- response_body_like eval
qr/"nodes":\{"127.0.0.1:1980":1\}/
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr{invalid item data of \[/apisix/services/1\], val: mexxxxxxxxxxxxxxx, it shoud be a object}



=== TEST 4: no error log
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]
