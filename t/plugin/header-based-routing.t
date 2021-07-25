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

=== TEST 1: schema validation passed
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.header-based-routing")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        match = {
                            {
                                name = "header1",
                                values = {
                                    "value1",
                                    "value2"
                                },
                                mode = "exact"
                            }
                        },
                        upstream_name = "my_upstream_1"
                    },
                    {
                        match = {
                            {
                                name = "header2",
                                values = {
                                    "1prefix",
                                    "2prefix"
                                },
                                mode = "prefix"
                            }
                        },
                        upstream_name = "my_upstream_2"
                    },
                    {
                        match = {
                            {
                                name = "header3",
                                values = {
                                    "(Twitterbot)/(\\d+)\\.(\\d+)"
                                },
                                mode = "regex"
                            }
                        },
                        upstream_name = "my_upstream_3"
                    },
                    {
                        match = {
                            {
                                name = "header4",
                                mode = "exists"
                            }
                        },
                        upstream_name = "my_upstream_4"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: schema validation failed, `match` configuration missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.header-based-routing")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        match_not_ok = {
                            {
                                name = "header4",
                                mode = "exists"
                            }
                        },
                        upstream_name = "my_upstream_1"
                    },
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/failed: failed to validate item 1: property "match" is required/



=== TEST 3: schema validation failed, `upstream_name` configuration missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.header-based-routing")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        match = {
                            {
                                name = "header4",
                                mode = "exists"
                            }
                        },
                    },
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/failed: failed to validate item 1: property "upstream_name" is required/



=== TEST 4: schema validation failed, `match.name` configuration missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.header-based-routing")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        match = {
                            {
                                mode = "exists"
                            }
                        },
                        upstream_name = "my_upstream_001"
                    },
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/property "match" validation failed: failed to validate item 1: property "name" is required/



=== TEST 5: schema validation failed, `match.mode` configuration missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.header-based-routing")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        match = {
                            {
                                name = "header1",
                            }
                        },
                        upstream_name = "my_upstream_1"
                    },
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/property "match" validation failed: failed to validate item 1: property "mode" is required/



=== TEST 6: schema validation failed, `match.values` configuration missing when mode is not `exists`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.header-based-routing")
            local ok, err = plugin.check_schema({
                rules = {
                    {
                        match = {
                            {
                                name = "header1",
                                mode = "exact"
                            }
                        },
                        upstream_name = "my_upstream_001"
                    },
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body eval
qr/failed to validate 'match.values'/



=== TEST 7: missing `rules` configuration, the upstream of the default `route` takes effect
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "header-based-routing": {}
                    },
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
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



=== TEST 8: the upstream of the default `route` takes effect
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local bodys = {}
        local _, _, body = t('/server_port', ngx.HTTP_GET)
        ngx.say(body)
    }
}
--- response_body
1980



=== TEST 9: set upstream with port 1981 1982
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body
            for i = 1, 2 do
                code, body = t('/apisix/admin/upstreams/' .. tostring(i),
                    ngx.HTTP_PUT,
                    string.format('{ "nodes": { "127.0.0.1:%s": 1 }, "type": "roundrobin", "name": "my_upstream_%s" }',
                     tostring(i + 1980), tostring(i)))
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say(body)
        }
    }
--- response_body
passed




=== TEST 10: test exact header match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    },
                    "plugins": {
                        "header-based-routing": {
                            "rules": [
                                {
                                  "match": [
                                    {
                                      "name": "header1",
                                      "values": [
                                        "value1",
                                        "value2"
                                      ],
                                      "mode": "exact"
                                    }
                                  ],
                                  "upstream_name": "my_upstream_1"
                                }
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



=== TEST 11: should hit default upstream
--- request
GET /server_port
--- error_code: 200
--- response_body chomp
1980



=== TEST 12: not hit exact match upstream
--- request
GET /server_port
--- more_headers
header1:value100
--- error_code: 200
--- response_body chomp
1980



=== TEST 13: should hit exact match upstream
--- request
GET /server_port
--- more_headers
header1:value1
--- error_code: 200
--- response_body chomp
1981



=== TEST 14: should hit exact match upstream with second header value
--- request
GET /server_port
--- more_headers
header1:value2
--- error_code: 200
--- response_body chomp
1981





=== TEST 15: test prefix header match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    },
                    "plugins": {
                        "header-based-routing": {
                            "rules": [
                                {
                                  "match": [
                                    {
                                      "name": "header2",
                                      "values": [
                                        "1prefix",
                                        "2prefix"
                                      ],
                                      "mode": "prefix"
                                    }
                                  ],
                                  "upstream_name": "my_upstream_2"
                                }
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



=== TEST 16: should hit default upstream
--- request
GET /server_port
--- error_code: 200
--- response_body chomp
1980



=== TEST 17: not hit exact prefix upstream
--- request
GET /server_port
--- more_headers
header2:3prefix
--- error_code: 200
--- response_body chomp
1980



=== TEST 18: should hit prefix match upstream
--- request
GET /server_port
--- more_headers
header2:1prefix_foo
--- error_code: 200
--- response_body chomp
1982



=== TEST 19: should hit prefix match upstream with second header value
--- request
GET /server_port
--- more_headers
header2:2prefix_bar
--- error_code: 200
--- response_body chomp
1982



=== TEST 20: test regex header match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    },
                    "plugins": {
                        "header-based-routing": {
                            "rules": [
                                {
                                  "match": [
                                    {
                                      "name": "header3",
                                      "values": [ "(Twitterbot)/(\\d+)\\.(\\d+)", "^[1-9][0-9]*" ],
                                      "mode": "regex"
                                    }
                                  ],
                                  "upstream_name": "my_upstream_1"
                                }
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




=== TEST 21: should hit default upstream
--- request
GET /server_port
--- error_code: 200
--- response_body chomp
1980



=== TEST 22: not hit regex upstream
--- request
GET /server_port
--- more_headers
header3:Twitterbotfoo
--- error_code: 200
--- response_body chomp
1980




=== TEST 23: should hit prefix match upstream
--- request
GET /server_port
--- more_headers
header3:Twitterbot/2.0
--- error_code: 200
--- response_body chomp
1981



=== TEST 24: should hit regex match upstream with second header value
--- request
GET /server_port
--- more_headers
header3:10
--- error_code: 200
--- response_body chomp
1981



=== TEST 25: test exists header match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                    },
                    "plugins": {
                        "header-based-routing": {
                            "rules": [
                                {
                                  "match": [
                                    {
                                      "name": "header4",
                                      "mode": "exists"
                                    }
                                  ],
                                  "upstream_name": "my_upstream_2"
                                }
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




=== TEST 26: should hit default upstream
--- request
GET /server_port
--- error_code: 200
--- response_body chomp
1980



=== TEST 27: not hit exists match upstream
--- request
GET /server_port
--- more_headers
header44:foo
--- error_code: 200
--- response_body chomp
1980




=== TEST 28: should hit exists match upstream
--- request
GET /server_port
--- more_headers
header4:foo
--- error_code: 200
--- response_body chomp
1982


=== TEST 29: set disable=true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "plugins": {
                        "header-based-routing": {
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
