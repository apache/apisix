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

=== TEST 1: validate metadata allow_origins
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cors")
            local schema_type = require("apisix.core").schema.TYPE_METADATA
            local function validate(val)
                local conf = {}
                conf.allow_origins = val
                return plugin.check_schema(conf, schema_type)
            end

            local good = {
                key_1 = "*",
                key_2 = "**",
                key_3 = "null",
                key_4 = "http://y.com.uk",
                key_5 = "https://x.com",
                key_6 = "https://x.com,http://y.com.uk",
                key_7 = "https://x.com,http://y.com.uk,http://c.tv",
                key_8 = "https://x.com,http://y.com.uk:12000,http://c.tv",
            }
            local ok, err = validate(good)
            if not ok then
                ngx.say("failed to validate ", g, ", ", err)
            end

            local bad = {
                "",
                "*a",
                "*,http://y.com",
                "nulll",
                "http//y.com.uk",
                "x.com",
                "https://x.com,y.com.uk",
                "https://x.com,*,https://y.com.uk",
                "https://x.com,http://y.com.uk,http:c.tv",
            }
            for _, b in ipairs(bad) do
                local ok, err = validate({key = b})
                if ok then
                    ngx.say("failed to reject ", b)
                end
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: set plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/cors',
                ngx.HTTP_PUT,
                [[{
                    "allow_origins": {
                        "key_1": "https://domain.com",
                        "key_2": "https://sub.domain.com,https://sub2.domain.com",
                        "key_3": "*"
                    },
                    "inactive_timeout": 1
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



=== TEST 3: set route (allow_origins_by_metadata specified)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "https://test.com",
                            "allow_origins_by_metadata": ["key_1"]
                        }
                    },
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
--- response_body
passed



=== TEST 4: origin not match
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://foo.example.org
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin:
Vary: Origin
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:



=== TEST 5: origin matches with allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: https://test.com
resp-vary: Via
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: https://test.com
Vary: Via, Origin
Access-Control-Allow-Methods: *
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:



=== TEST 6: origin matches with allow_origins_by_metadata
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: https://domain.com
resp-vary: Via
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: https://domain.com
Vary: Via, Origin
Access-Control-Allow-Methods: *
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:



=== TEST 7: set route (multiple allow_origins_by_metadata specified)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "https://test.com",
                            "allow_origins_by_metadata": ["key_1", "key_2"]
                        }
                    },
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
--- response_body
passed



=== TEST 8: origin not match
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://foo.example.org
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin:
Vary: Origin
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:



=== TEST 9: origin matches with first allow_origins_by_metadata
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: https://domain.com
resp-vary: Via
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: https://domain.com
Vary: Via, Origin
Access-Control-Allow-Methods: *
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:



=== TEST 10: origin matches with second allow_origins_by_metadata
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: https://sub.domain.com
resp-vary: Via
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: https://sub.domain.com
Vary: Via, Origin
Access-Control-Allow-Methods: *
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:



=== TEST 11: set route (wildcard in allow_origins_by_metadata)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "https://test.com",
                            "allow_origins_by_metadata": ["key_3"]
                        }
                    },
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
--- response_body
passed



=== TEST 12: origin matches by wildcard
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://foo.example.org
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: http://foo.example.org
Vary: Origin
Access-Control-Allow-Methods: *
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:



=== TEST 13: set route (allow_origins_by_metadata specified and allow_origins * is invalid while set allow_origins_by_metadata)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "*",
                            "allow_origins_by_metadata": ["key_1"]
                        }
                    },
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
--- response_body
passed



=== TEST 14: origin not match
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://foo.example.org
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:



=== TEST 15: origin matches with first allow_origins_by_metadata
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: https://domain.com
--- response_body
hello world
--- response_headers
Access-Control-Allow-Origin: https://domain.com
Access-Control-Allow-Methods: *
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Access-Control-Max-Age: 5
Access-Control-Allow-Credentials:
