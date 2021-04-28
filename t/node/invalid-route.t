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

=== TEST 1: set invalid route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/routes/1", [[mexxxxxxxxxxxxxxx]])

            if res.status >= 300 then
                res.status = code
            end

            ngx.print(require("toolkit.json").encode(res.body))
            ngx.sleep(1)
        }
    }
--- request
GET /t
--- wait: 1
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr{invalid item data of \[/apisix/routes/1\], val: mexxxxxxxxxxxxxxx, it should be an object}
--- response_body_like eval
qr/"value":"mexxxxxxxxxxxxxxx"/



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}
--- wait: 1
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr{invalid item data of \[/apisix/routes/1\], val: mexxxxxxxxxxxxxxx, it should be an object}



=== TEST 3: set valid route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- wait: 1
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr{invalid item data of \[/apisix/routes/1\], val: mexxxxxxxxxxxxxxx, it should be an object}



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



=== TEST 5: set route(with invalid host)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "key": "remote_addr",
                        "type": "chash",
                        "nodes": {
                            "xxxx.invalid:1980": 1
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: hit route
--- request
GET /server_port
--- error_code: 503
--- error_log
failed to parse domain: xxxx.invalid
--- timeout: 10
