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

add_block_preprocessor(sub {
    my ($block) = @_;

    # $block->set_value("stream_conf_enable", 1);

    if (!defined $block->additional_http_config) {
        my $inside_lua_block = $block->inside_lua_block // "";
        chomp($inside_lua_block);
        my $test_config = <<_EOC_;

        listen 8765;
        location /azure-demo {
            content_by_lua_block {
                $inside_lua_block
            }
        }
_EOC_
        $block->set_value("additional_http_config", $test_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.azure-functions")
            local conf = {
                function_uri = "http://some-url.com"
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: function_uri missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.azure-functions")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
property "function_uri" is required



=== TEST 3: create route with azure-function plugin enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "azure-functions": {
                                "function_uri": "http://localhost:8765/azure-demo"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/azure"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "azure-functions": {
                                    "keepalive": true,
                                    "timeout": 3000,
                                    "ssl_verify": true,
                                    "keepalive_timeout": 60000,
                                    "keepalive_pool": 5,
                                    "function_uri": "http://localhost:8765/azure-demo"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/azure"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: Test plugin endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, body = t("/azure", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- inside_lua_block
ngx.say("faas invoked")
--- response_body
faas invoked



=== TEST 5: check authz header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- passing an apikey
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "azure-functions": {
                                "function_uri": "http://localhost:8765/azure-demo",
                                "authorization": {
                                    "apikey": "test_key"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/azure"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            local code, _, body = t("/azure", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- inside_lua_block
local headers = ngx.req.get_headers() or {}
ngx.say("Authz-Header - " .. headers["x-functions-key"] or "")

--- response_body
passed
Authz-Header - test_key
