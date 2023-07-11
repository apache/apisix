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
                host = 'apisix.iresty.com'
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
--- response_body
passed



=== TEST 13: rewrite X-Forwarded-Host
--- request
GET /echo HTTP/1.1
--- more_headers
X-Forwarded-Host: apisix.ai
--- response_headers
X-Forwarded-Host: test.com



=== TEST 14: set route header test
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
                                    "add":{"test": "123"},
                                    "set":{"test2": "2233"},
                                    "remove":["hello"]
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
--- response_body
passed



=== TEST 15: add exist header in muti-header
--- request
GET /echo HTTP/1.1
--- more_headers
test: sssss
test: bbb
--- response_headers
test: sssss, bbb, 123



=== TEST 16: add header to exist header
--- request
GET /echo HTTP/1.1
--- more_headers
test: sssss
--- response_headers
test: sssss, 123



=== TEST 17: remove header
--- request
GET /echo HTTP/1.1
--- more_headers
hello: word
--- response_headers
hello:



=== TEST 18: set header success
--- request
GET /echo HTTP/1.1
--- response_headers
test2: 2233



=== TEST 19: header priority test
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
                                    "add":{"test": "test_in_add"},
                                    "set":{"test": "test_in_set"}
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
--- response_body
passed



=== TEST 20: set and test priority test & deprecated calls test
--- request
GET /echo HTTP/1.1
--- response_headers
test: test_in_set
--- no_error_log
DEPRECATED: use add_header(ctx, header_name, header_value) instead
DEPRECATED: use set_header(ctx, header_name, header_value) instead



=== TEST 21: set route
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



=== TEST 22: hit with CRLF
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



=== TEST 23: set route with uri
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



=== TEST 24: hit with CRLF
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



=== TEST 25: regex_uri with args
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



=== TEST 26: hit
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



=== TEST 27: use variables in headers when captured by regex_uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "uri": "/test/*",
                      "plugins": {
                        "proxy-rewrite": {
                            "regex_uri": ["^/test/(.*)/(.*)/(.*)", "/echo"],
                            "headers": {
                                "add": {
                                    "X-Request-ID": "$1/$2/$3"
                                }
                            }
                        }
                      },
                      "upstream": {
                          "nodes": {
                              "127.0.0.1:1980": 1
                          },
                          "type": "roundrobin"
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



=== TEST 28: hit
--- request
GET /test/plugin/proxy/rewrite HTTP/1.1
--- response_headers
X-Request-ID: plugin/proxy/rewrite



=== TEST 29: use variables in header when not matched regex_uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "uri": "/echo*",
                      "plugins": {
                        "proxy-rewrite": {
                            "regex_uri": ["^/test/(.*)/(.*)/(.*)", "/echo"],
                            "headers": {
                                "add": {
                                    "X-Request-ID": "$1/$2/$3"
                                }
                            }
                        }
                      },
                      "upstream": {
                          "nodes": {
                              "127.0.0.1:1980": 1
                          },
                          "type": "roundrobin"
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



=== TEST 30: hit
--- request
GET /echo HTTP/1.1
--- more_headers
X-Foo: Foo
--- response_headers
X-Foo: Foo



=== TEST 31: use variables in headers when captured by regex_uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "uri": "/test/*",
                      "plugins": {
                        "proxy-rewrite": {
                            "regex_uri": ["^/test/(not_matched)?.*", "/echo"],
                            "headers": {
                                "add": {
                                    "X-Request-ID": "test1/$1/$2/test2"
                                }
                            }
                        }
                      },
                      "upstream": {
                          "nodes": {
                              "127.0.0.1:1980": 1
                          },
                          "type": "roundrobin"
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



=== TEST 32: hit
--- request
GET /test/plugin/proxy/rewrite HTTP/1.1
--- response_headers
X-Request-ID: test1///test2



=== TEST 33: set route (test if X-Forwarded-Port can be set before proxy)
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
                                    "X-Forwarded-Port": "9882"
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



=== TEST 34: test if X-Forwarded-Port can be set before proxy
--- request
GET /echo HTTP/1.1
--- more_headers
X-Forwarded-Port: 9881
--- response_headers
X-Forwarded-Port: 9882



=== TEST 35: set route (test if X-Forwarded-For can be set before proxy)
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
                                    "X-Forwarded-For": "22.22.22.22"
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



=== TEST 36: test if X-Forwarded-For can be set before proxy
--- request
GET /echo HTTP/1.1
--- more_headers
X-Forwarded-For: 11.11.11.11
--- response_headers
X-Forwarded-For: 22.22.22.22, 127.0.0.1



=== TEST 37: setting multiple regex_uris
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "plugins": {
                          "proxy-rewrite": {
                              "regex_uri": [
                                  "^/test/(.*)/(.*)/(.*)/hello",
                                  "/hello/$1_$2_$3",
                                  "^/test/(.*)/(.*)/(.*)/world",
                                  "/world/$1_$2_$3"
                              ]
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



=== TEST 38: hit
--- request
GET /test/plugin/proxy/rewrite/hello HTTP/1.1
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
/hello/plugin_proxy_rewrite



=== TEST 39: hit
--- request
GET /test/plugin/proxy/rewrite/world HTTP/1.1
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
/world/plugin_proxy_rewrite



=== TEST 40: use regex uri with unsafe allowed
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "plugins": {
                          "proxy-rewrite": {
                              "regex_uri": [
                                  "/hello/(.+)",
                                  "/hello?unsafe_variable=$1"
                              ],
                              "use_real_request_uri_unsafe": true
                           }
                        },
                      "upstream": {
                          "nodes": {
                              "127.0.0.1:8125": 1
                          },
                          "type": "roundrobin"
                      },
                      "uri": "/hello/*"
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



=== TEST 41: hit
--- request
GET /hello/%ED%85%8C%EC%8A%A4%ED%8A%B8 HTTP/1.1
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
/hello?unsafe_variable=%ED%85%8C%EC%8A%A4%ED%8A%B8
