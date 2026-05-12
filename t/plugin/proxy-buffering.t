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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: schema validation - sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-buffering")
            local ok, err = plugin.check_schema({disable_proxy_buffering = true})
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: schema validation - invalid type
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-buffering")
            local ok, err = plugin.check_schema({disable_proxy_buffering = "yes"})
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
property "disable_proxy_buffering" validation failed: wrong type: expected boolean, got string



=== TEST 3: schema validation - default value is false
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-buffering")
            local conf = {}
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(conf.disable_proxy_buffering)
        }
    }
--- response_body
false



=== TEST 4: set disable_proxy_buffering=true on a route
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
                        "proxy-buffering": {
                            "disable_proxy_buffering": true
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
--- response_body
passed



=== TEST 5: hit route with disable_proxy_buffering=true, response is successful
--- request
GET /hello
--- response_body
hello world



=== TEST 6: set disable_proxy_buffering=false (default buffering)
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
                        "proxy-buffering": {
                            "disable_proxy_buffering": false
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
--- response_body
passed



=== TEST 7: hit route with disable_proxy_buffering=false, response is successful
--- request
GET /hello
--- response_body
hello world
