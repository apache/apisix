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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

no_long_string();
no_root_location();
log_level("info");
run_tests;

__DATA__

=== TEST 1: ensure all plugins have exposed their name
--- config
    location /t {
        content_by_lua_block {
            local lfs = require("lfs")
            for file_name in lfs.dir(ngx.config.prefix() .. "/../../apisix/plugins/") do
                if string.match(file_name, ".lua$") then
                    local expected = file_name:sub(1, #file_name - 4)
                    local plugin = require("apisix.plugins." .. expected)
                    if plugin.name ~= expected then
                        ngx.say("expected ", expected, " got ", plugin.name)
                        return
                    end
                end
            end
            ngx.say('ok')
        }
    }
--- response_body
ok



=== TEST 2: define route for /*
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key"
                        }
                    }
                }]])

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: sign and verify
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err, sign = t('/apisix/plugin/jwt/sign?key=user-key',
                ngx.HTTP_GET
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end

            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- request
GET /t
--- response_body
hello world



=== TEST 4: delete /* and define route for /apisix/plugin/blah
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1', "DELETE")
            if code >= 300 then
                ngx.status = code
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/apisix/plugin/blah"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: hit
--- request
GET /apisix/plugin/blah
--- error_code: 401
--- response_body
{"message":"Missing JWT token in request"}
