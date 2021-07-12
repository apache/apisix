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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: empty conf
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.bot-restriction")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- error_code: 200



=== TEST 2: set whitelist, blacklist and user-defined message
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.bot-restriction")
            local conf = {
               whitelist = {
                    "my-bot1",
                    "my-bot2"
               },
               blacklist = {
                    "my-bot1",
                    "my-bot2"
               },
               message = "User-Agent Forbidden",
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body
{"blacklist":["my-bot1","my-bot2"],"message":"User-Agent Forbidden","whitelist":["my-bot1","my-bot2"]}



=== TEST 3: whitelist not array
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.bot-restriction")
            local conf = {
                whitelist = "my-bot1",
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "whitelist" validation failed: wrong type: expected array, got string
done



=== TEST 4: blacklist not array
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.bot-restriction")
            local conf = {
                blacklist = 100,
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "blacklist" validation failed: wrong type: expected array, got number
done



=== TEST 5: message not string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.bot-restriction")
            local conf = {
                message = 100,
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "message" validation failed: wrong type: expected string, got number
done



=== TEST 6: set blacklist

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
                            "bot-restriction": {
                                 "blacklist": [
                                     "my-bot1",
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
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
--- response_body
passed



=== TEST 7: hit route and user-agent in blacklist

--- request
GET /hello
--- more_headers
User-Agent:my-bot1
--- error_code: 403



=== TEST 8: hit route and user-agent in blacklist with multiple

--- request
GET /hello
--- more_headers
User-Agent:my-bot1
User-Agent:my-bot1
--- error_code: 200



=== TEST 9: hit route and user-agent match blacklist regex

--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/3.0
--- error_code: 403



=== TEST 10: hit route and user-agent not in blacklist

--- request
GET /hello
--- more_headers
User-Agent:foo/bar
--- error_code: 200



=== TEST 11: set whitelist

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
                            "bot-restriction": {
                                 "whitelist": [
                                     "my-bot1",
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
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
--- response_body
passed



=== TEST 12: hit route and user-agent in whitelist

--- request
GET /hello
--- more_headers
User-Agent:my-bot1
--- error_code: 200



=== TEST 13: hit route and user-agent match whitelist regex

--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/3.0
--- error_code: 200



=== TEST 14: hit route and user-agent not in whitelist

--- request
GET /hello
--- more_headers
User-Agent:foo/bar
--- error_code: 200



=== TEST 15: set rules to default
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
                            "bot-restriction": {
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



=== TEST 16: hit route and user-agent in default list

--- request
GET /hello
--- more_headers
User-Agent:Twitterbot/1.0
--- error_code: 403



=== TEST 17: set config: user-agent in both whitelist and blacklist
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
                            "bot-restriction": {
                                 "whitelist": [
                                     "foo/bar",
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
                                 ],
                                 "blacklist": [
                                     "foo/bar",
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
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
--- response_body
passed



=== TEST 18: hit route and user-agent in both whitelist and blacklist, part 1

--- request
GET /hello
--- more_headers
User-Agent:foo/bar
--- error_code: 200



=== TEST 19: hit route and user-agent in both whitelist and blacklist, part 2

--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/1.0
--- error_code: 200



=== TEST 20: set config: user-agent in both whitelist and default deny list
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
                            "bot-restriction": {
                                 "whitelist": [
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
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
--- response_body
passed



=== TEST 21: hit route and user-agent in both whitelist and default deny list

--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/1.0
--- error_code: 200



=== TEST 22: message that do not reach the minimum range
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
                            "bot-restriction": {
                                 "message": ""
                            }
                        }
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body_like eval
qr/string too short, expected at least 1, got 0/



=== TEST 23: exceeds the maximum limit of message
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")

            local data = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1,
                    }
                },
                plugins = {
                    ["bot-restriction"] = {
                        message = ("-1Aa#"):rep(205)
                    }
                }
            }

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            ngx.say(body)
        }
    }
--- response_body_like eval
qr/string too long, expected at most 1024, got 1025/



=== TEST 24: set custom message
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
                            "bot-restriction": {
                                 "message": "Do you want to do something bad?"
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



=== TEST 25: test custom message
--- request
GET /hello
--- more_headers
User-Agent:Twitterbot/1.0
--- error_code: 403
--- response_body
{"message":"Do you want to do something bad?"}



=== TEST 26: test remove bot-restriction part 1
--- config
    location /enable {
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
                        "bot-restriction": {
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

    location /disable {
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
GET /enable
--- error_code: 200



=== TEST 27: test remove bot-restriction part 2
--- request
GET /hello
--- more_headers
User-Agent:Twitterbot/1.0
--- error_code: 403



=== TEST 28: test remove bot-restriction part 3, remove plugin
--- config
    location /disable {
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
GET /disable
--- error_code: 200



=== TEST 29: test remove bot-restriction part 4, check bot User-Agent
--- request
GET /hello
--- more_headers
User-Agent:Twitterbot/1.0
--- response_body
hello world



=== TEST 30: set disable=true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "bot-restriction": {
                            "blacklist": [
                                "foo"
                            ],
                            "disable": true
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
