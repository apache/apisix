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

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("no_error_log", "[error]");

    $block;
});

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: set whitelist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "referer-restriction": {
                                 "whitelist": [
                                     "*.xx.com",
                                     "yy.com"
                                 ]
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



=== TEST 2: hit route and in the whitelist (wildcard)
--- request
GET /hello
--- more_headers
Referer: http://www.xx.com
--- response_body
hello world



=== TEST 3: hit route and in the whitelist
--- request
GET /hello
--- more_headers
Referer: https://yy.com/am
--- response_body
hello world



=== TEST 4: hit route and not in the whitelist
--- request
GET /hello
--- more_headers
Referer: https://www.yy.com/am
--- error_code: 403



=== TEST 5: hit route and without Referer
--- request
GET /hello
--- error_code: 403



=== TEST 6: set whitelist, allow Referer missing
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "referer-restriction": {
                                "bypass_missing": true,
                                 "whitelist": [
                                     "*.xx.com",
                                     "yy.com"
                                 ]
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



=== TEST 7: hit route and without Referer
--- request
GET /hello
--- response_body
hello world



=== TEST 8: malformed Referer is treated as missing
--- request
GET /hello
--- more_headers
Referer: www.yy.com
--- response_body
hello world



=== TEST 9: invalid schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.referer-restriction")
            local cases = {
                "x.*",
                "~y.xn",
                "::1",
            }
            for _, c in ipairs(cases) do
                local ok, err = plugin.check_schema({
                    whitelist = {c}
                })
                if ok then
                    ngx.log(ngx.ERR, c)
                end
            end
        }
    }
--- request
GET /t
