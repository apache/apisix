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

=== TEST 1: validate timing_allow_origins
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cors")
            local function validate(val)
                local conf = {}
                conf.timing_allow_origins = val
                return plugin.check_schema(conf)
            end

            local good = {
                "*",
                "**",
                "null",
                "http://y.com.uk",
                "https://x.com",
                "https://x.com,http://y.com.uk",
                "https://x.com,http://y.com.uk,http://c.tv",
                "https://x.com,http://y.com.uk:12000,http://c.tv",
            }
            for _, g in ipairs(good) do
                local ok, err = validate(g)
                if not ok then
                    ngx.say("failed to validate ", g, ", ", err)
                end
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
                local ok, err = validate(b)
                if ok then
                    ngx.say("failed to reject ", b)
                end
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: set route ( allow_origins default, timing_allow_origins specified )
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
                            "allow_methods": "GET,POST",
                            "allow_headers": "request-h",
                            "expose_headers": "expose-h",
                            "max_age": 10,
                            "timing_allow_origins": "http://sub.domain.com"
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
--- request
GET /t
--- response_body
passed



=== TEST 3: origin matching
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://sub.domain.com
--- response_headers
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Access-Control-Allow-Credentials:
Timing-Allow-Origin: http://sub.domain.com



=== TEST 4: origin not matching timing_allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://other.domain.com
--- response_headers
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Access-Control-Allow-Credentials:
Timing-Allow-Origin:



=== TEST 5: set route ( allow_origins same as timing_allow_origins )
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "http://sub.domain.com",
                            "allow_methods": "GET,POST",
                            "allow_headers": "request-h",
                            "expose_headers": "expose-h",
                            "max_age": 10,
                            "timing_allow_origins": "http://sub.domain.com"
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
--- request
GET /t
--- response_body
passed



=== TEST 6: origin matching
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://sub.domain.com
--- response_headers
Access-Control-Allow-Origin: http://sub.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Access-Control-Allow-Credentials:
Timing-Allow-Origin: http://sub.domain.com



=== TEST 7: origin not matching
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://other.domain.com
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:
Timing-Allow-Origin:



=== TEST 8: set route ( allow_origins differs from timing_allow_origins )
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "http://one.domain.com",
                            "allow_methods": "GET,POST",
                            "allow_headers": "request-h",
                            "expose_headers": "expose-h",
                            "max_age": 10,
                            "timing_allow_origins": "http://another.domain.com"
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
--- request
GET /t
--- response_body
passed



=== TEST 9: origin matching allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://one.domain.com
--- response_headers
Access-Control-Allow-Origin: http://one.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Access-Control-Allow-Credentials:
Timing-Allow-Origin:



=== TEST 10: origin matching timing_allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://another.domain.com
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:
Timing-Allow-Origin: http://another.domain.com



=== TEST 11: origin not matching
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://notexistent.domain.com
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:
Timing-Allow-Origin:



=== TEST 12: set route ( allow_origins superset of timing_allow_origins )
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "http://one.domain.com,http://two.domain.com",
                            "allow_methods": "GET,POST",
                            "allow_headers": "request-h",
                            "expose_headers": "expose-h",
                            "max_age": 10,
                            "timing_allow_origins": "http://one.domain.com"
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
--- request
GET /t
--- response_body
passed



=== TEST 13: origin matching allow_origins and timing_allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://one.domain.com
--- response_headers
Access-Control-Allow-Origin: http://one.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Access-Control-Allow-Credentials:
Timing-Allow-Origin: http://one.domain.com



=== TEST 14: origin matching only allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://two.domain.com
--- response_headers
Access-Control-Allow-Origin: http://two.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Access-Control-Allow-Credentials:
Timing-Allow-Origin:



=== TEST 15: origin not matching
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://notexistent.domain.com
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:
Timing-Allow-Origin:



=== TEST 16: set route ( allow_origins and timing_allow_origins are two different sets with intersection )
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins": "http://one.domain.com,http://two.domain.com",
                            "allow_methods": "GET,POST",
                            "allow_headers": "request-h",
                            "expose_headers": "expose-h",
                            "max_age": 10,
                            "timing_allow_origins": "http://one.domain.com,http://three.domain.com"
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
--- request
GET /t
--- response_body
passed



=== TEST 17: origin matching allow_origins and timing_allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://one.domain.com
--- response_headers
Access-Control-Allow-Origin: http://one.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Access-Control-Allow-Credentials:
Timing-Allow-Origin: http://one.domain.com



=== TEST 18: origin matching only allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://two.domain.com
--- response_headers
Access-Control-Allow-Origin: http://two.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Access-Control-Allow-Credentials:
Timing-Allow-Origin:



=== TEST 19: origin matching only timing_allow_origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://three.domain.com
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:
Timing-Allow-Origin: http://three.domain.com



=== TEST 20: origin not matching
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://notexistent.domain.com
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Access-Control-Allow-Credentials:
Timing-Allow-Origin:



=== TEST 21: set route ( allow_origins and timing_allow_origins specified with regex )
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins_by_regex": ["http://.*?\\.domain\\.com"],
                            "allow_methods": "GET,POST",
                            "allow_headers": "request-h",
                            "expose_headers": "expose-h",
                            "max_age": 10,
                            "timing_allow_origins_by_regex": ["http://.*?\\.domain\\.com"]
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
--- request
GET /t
--- response_body
passed



=== TEST 22: regex specified match
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://sub.domain.com
--- response_headers
Access-Control-Allow-Origin: http://sub.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Timing-Allow-Origin: http://sub.domain.com



=== TEST 23: regex no match
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://other.newdomain.com
--- response_headers
Access-Control-Allow-Origin:
Access-Control-Allow-Methods:
Access-Control-Allow-Headers:
Access-Control-Expose-Headers:
Access-Control-Max-Age:
Timing-Allow-Origin:



=== TEST 24: set route ( allow_origins and timing_allow_origins specified with different regex )
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_origins_by_regex": ["http://.*?\\.domain\\.com"],
                            "allow_methods": "GET,POST",
                            "allow_headers": "request-h",
                            "expose_headers": "expose-h",
                            "max_age": 10,
                            "timing_allow_origins_by_regex": ["http://test.*?\\.domain\\.com"],
                            "timing_allow_origins": "http://nonexistent.newdomain.com"
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
--- request
GET /t
--- response_body
passed



=== TEST 25: regex specified match, test priority of regex over list of origins
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://testurl.domain.com
--- response_headers
Access-Control-Allow-Origin: http://testurl.domain.com
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Headers: request-h
Access-Control-Expose-Headers: expose-h
Access-Control-Max-Age: 10
Timing-Allow-Origin: http://testurl.domain.com



=== TEST 26: set route ( expose_headers not specified )
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_credential": true,
                            "allow_headers": "**",
                            "allow_methods": "**",
                            "allow_origins": "**",
                            "expose_headers": "",
                            "max_age": 3500
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
--- request
GET /t
--- response_body
passed



=== TEST 27: remove Access-Control-Expose-Headers match
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://sub.domain.com
--- response_headers
Access-Control-Allow-Origin: http://sub.domain.com
Access-Control-Allow-Methods: GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS,CONNECT,TRACE
Access-Control-Allow-Headers:
Access-Control-Max-Age: 3500
Access-Control-Allow-Credentials: true



=== TEST 28: set route ( expose_headers set value )
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "cors": {
                            "allow_credential": true,
                            "allow_headers": "**",
                            "allow_methods": "**",
                            "allow_origins": "**",
                            "expose_headers": "ex-headr1,ex-headr2",
                            "max_age": 3500
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
--- request
GET /t
--- response_body
passed



=== TEST 29: Access-Control-Expose-Headers match
--- request
GET /hello HTTP/1.1
--- more_headers
Origin: http://sub.domain.com
--- response_headers
Access-Control-Allow-Origin: http://sub.domain.com
Access-Control-Allow-Methods: GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS,CONNECT,TRACE
Access-Control-Expose-Headers: ex-headr1,ex-headr2
Access-Control-Allow-Headers:
Access-Control-Max-Age: 3500
Access-Control-Allow-Credentials: true
