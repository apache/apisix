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

=== TEST 1: set route(rewrite method)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "method": "POST",
                                "scheme": "http",
                                "host": "apisix.iresty.com"
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



=== TEST 2: hit route(upstream uri: should be /hello)
--- request
GET /hello
--- error_log
plugin_proxy_rewrite get method: POST



=== TEST 3: set route(update rewrite method)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "method": "GET",
                                "scheme": "http",
                                "host": "apisix.iresty.com"
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



=== TEST 4: hit route(upstream uri: should be /hello)
--- request
GET /hello
--- error_log
plugin_proxy_rewrite get method: GET



=== TEST 5: wrong value of method key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local ok, err = plugin.check_schema({
                uri = '/apisix/home',
                method = 'GET1',
                host = 'apisix.iresty.com',
                scheme = 'http'
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "method" validation failed: matches none of the enum values
done



=== TEST 6: set route(rewrite method with headers)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "method": "POST",
                                "scheme": "http",
                                "host": "apisix.iresty.com",
                                "headers":{
                                    "x-api-version":"v1"
                                }
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



=== TEST 7: hit route(with header)
--- request
GET /hello
--- error_log
plugin_proxy_rewrite get method: POST



=== TEST 8: set route(unsafe uri not normalized at request)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "use_real_request_uri_unsafe": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/print_uri_detailed"
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



=== TEST 9: unsafe uri not normalized at request
--- request
GET /print%5Furi%5Fdetailed HTTP/1.1
--- response_body
ngx.var.uri: /print_uri_detailed
ngx.var.request_uri: /print%5Furi%5Fdetailed



=== TEST 10: set route(safe uri not normalized at request)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "use_real_request_uri_unsafe": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/print_uri_detailed"
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



=== TEST 11: safe uri not normalized at request
--- request
GET /print_uri_detailed HTTP/1.1
--- response_body
ngx.var.uri: /print_uri_detailed
ngx.var.request_uri: /print_uri_detailed



=== TEST 12: set route(rewrite X-Forwarded-Host)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "headers": {
                                    "X-Forwarded-Host": "test.com"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 13: rewrite X-Forwarded-Host
--- request
GET /echo HTTP/1.1
--- more_headers
X-Forwarded-Host: apisix.ai
--- response_headers
X-Forwarded-Host: test.com



=== TEST 14: set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "plugins": {
                          "proxy-rewrite": {
                              "host": "test.xxxx.com"
                          }
                      },
                      "upstream": {
                          "nodes": {
                              "127.0.0.1:8125": 1
                          },
                          "type": "roundrobin"
                      },
                      "uri": "/hello*"
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



=== TEST 15: hit with CRLF
--- request
GET /hello%3f0z=700%26a=c%20HTTP/1.1%0D%0AHost:google.com%0d%0a%0d%0a
--- http_config
    server {
        listen 8125;
        location / {
            content_by_lua_block {
                ngx.say(ngx.var.host)
                ngx.say(ngx.var.request_uri)
            }
        }
    }
--- response_body
test.xxxx.com
/hello%3F0z=700&a=c%20HTTP/1.1%0D%0AHost:google.com%0D%0A%0D%0A



=== TEST 16: set route with uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "plugins": {
                          "proxy-rewrite": {
                              "uri": "/$uri/remain",
                              "host": "test.xxxx.com"
                          }
                      },
                      "upstream": {
                          "nodes": {
                              "127.0.0.1:8125": 1
                          },
                          "type": "roundrobin"
                      },
                      "uri": "/hello*"
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



=== TEST 17: hit with CRLF
--- request
GET /hello%3f0z=700%26a=c%20HTTP/1.1%0D%0AHost:google.com%0d%0a%0d%0a
--- http_config
    server {
        listen 8125;
        location / {
            content_by_lua_block {
                ngx.say(ngx.var.host)
                ngx.say(ngx.var.request_uri)
            }
        }
    }
--- response_body
test.xxxx.com
//hello%253F0z=700&a=c%20HTTP/1.1%0D%0AHost:google.com%0D%0A%0D%0A/remain



=== TEST 18: regex_uri with args
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "plugins": {
                          "proxy-rewrite": {
                              "regex_uri": ["^/test/(.*)/(.*)/(.*)", "/$1_$2_$3?a=c"]
                          }
                      },
                      "upstream": {
                          "nodes": {
                              "127.0.0.1:8125": 1
                          },
                          "type": "roundrobin"
                      },
                      "uri": "/test/*"
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



=== TEST 19: hit
--- request
GET /test/plugin/proxy/rewrite HTTP/1.1
--- http_config
    server {
        listen 8125;
        location / {
            content_by_lua_block {
                ngx.say(ngx.var.request_uri)
            }
        }
    }
--- response_body
/plugin_proxy_rewrite?a=c
