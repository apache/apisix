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
log_level('info');
worker_connections(1024);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 1986;
        server_tokens off;

        location / {
            content_by_lua_block {
                local core = require("apisix.core")
                core.log.info("upstream_http_version: ", ngx.req.http_version())

                local headers_tab = ngx.req.get_headers()
                local headers_key = {}
                for k in pairs(headers_tab) do
                    core.table.insert(headers_key, k)
                end
                core.table.sort(headers_key)

                for _, v in pairs(headers_key) do
                    core.log.info(v, ": ", headers_tab[v])
                end

                core.log.info("uri: ", ngx.var.request_uri)
                ngx.say("hello world")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity check (invalid schema)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "ftp://127.0.0.1:1999"
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
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-mirror/



=== TEST 2: sanity check (invalid port format)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1::1999"
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
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-mirror/



=== TEST 3: sanity check (without schema)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "127.0.0.1:1999"
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
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-mirror/



=== TEST 4: sanity check (without port)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1"
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
--- error_code: 200
--- response_body
passed



=== TEST 5: sanity check (include uri)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1999/invalid_uri"
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
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-mirror/



=== TEST 6: sanity check (normal case)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986"
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
--- error_code: 200
--- response_body
passed



=== TEST 7: hit route
--- request
GET /hello
--- error_code: 200
--- response_body
hello world
--- error_log
uri: /hello



=== TEST 8: sanity check (normal case), and uri is "/uri"
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/uri"
                   }]]
                   )

               if code >= 300 then
                   ngx.status = code
               end
               ngx.say(body)
           }
        }
--- error_code: 200
--- response_body
passed



=== TEST 9: the request header does not change
--- request
GET /uri
--- error_code: 200
--- more_headers
host: 127.0.0.2
api-key: hello
api-key2: world
name: jake
--- response_body
uri: /uri
api-key: hello
api-key2: world
host: 127.0.0.2
name: jake
x-real-ip: 127.0.0.1
--- error_log
api-key: hello
api-key2: world
host: 127.0.0.2
name: jake



=== TEST 10: sanity check (normal case), used to test http version
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986"
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
--- error_code: 200
--- response_body
passed



=== TEST 11: after the mirroring request, the upstream http version is 1.1
--- request
GET /hello
--- error_code: 200
--- more_headers
host: 127.0.0.2
api-key: hello
--- response_body
hello world
--- error_log
upstream_http_version: 1.1
api-key: hello
host: 127.0.0.2



=== TEST 12: delete route
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)

               if code >= 300 then
                   ngx.status = code
               end
               ngx.say(body)
           }
        }
--- error_code: 200
--- response_body
passed



=== TEST 13: sanity check (invalid sample_ratio)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986",
                               "sample_ratio": 10
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
               ngx.print(body)
           }
       }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin proxy-mirror err: property \"sample_ratio\" validation failed: expected 10 to be at most 1"}



=== TEST 14: set mirror requests sample_ratio to 1
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986",
                               "sample_ratio": 1
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
--- error_code: 200
--- response_body
passed



=== TEST 15: hit route with sample_ratio 1
--- request
GET /hello?sample_ratio=1
--- error_code: 200
--- response_body
hello world
--- error_log_like eval
qr/uri: \/hello\?sample_ratio=1/



=== TEST 16: set mirror requests sample_ratio to 0.5
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986",
                               "sample_ratio": 0.5
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
--- error_code: 200
--- response_body
passed



=== TEST 17: send batch requests and get mirror stat count
--- config
       location /t {
           content_by_lua_block {
                local t = require("lib.test_admin").test

                -- send batch requests
                local tb = {}
                for i = 1, 200 do
                    local th = assert(ngx.thread.spawn(function(i)
                        t('/hello?sample_ratio=0.5', ngx.HTTP_GET)
                    end, i))
                    table.insert(tb, th)
                end
                for i, th in ipairs(tb) do
                    ngx.thread.wait(th)
                end
           }
       }
--- error_log_like eval
qr/(uri: \/hello\?sample_ratio=0\.5){75,125}/



=== TEST 18: custom path
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986",
                               "path": "/a"
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



=== TEST 19: hit route
--- request
GET /hello
--- response_body
hello world
--- error_log
uri: /a,



=== TEST 20: hit route with args
--- request
GET /hello?a=1
--- response_body
hello world
--- error_log
uri: /a?a=1



=== TEST 21: sanity check (path)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               for _, p in ipairs({
                    "a",
                    "/a?a=c",
               }) do
                    local code, body = t('/apisix/admin/routes/1',
                        ngx.HTTP_PUT,
                        [[{
                            "plugins": {
                                "proxy-mirror": {
                                    "host": "http://127.0.0.1:1999",
                                    "path": "]] .. p .. [["
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
                    ngx.log(ngx.WARN, body)
                end
            }
       }
--- grep_error_log eval
qr/property \\"path\\" validation failed: failed to match pattern/
--- grep_error_log_out
property \"path\" validation failed: failed to match pattern
property \"path\" validation failed: failed to match pattern



=== TEST 22: sanity check (host)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               for _, p in ipairs({
                    "http://a",
                    "http://ab.com",
                    "http://[::1]",
                    "http://[::1]:202",
               }) do
                    local code, body = t('/apisix/admin/routes/1',
                        ngx.HTTP_PUT,
                        [[{
                            "plugins": {
                                "proxy-mirror": {
                                    "host": "]] .. p .. [["
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
                    ngx.log(ngx.WARN, body)
                end
           }
       }
--- grep_error_log eval
qr/(passed|property \\"host\\" validation failed: failed to match pattern)/
--- grep_error_log_out
passed
passed
passed
passed



=== TEST 23: set mirror requests host to domain
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://test.com:1980",
                               "path": "/hello"
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



=== TEST 24: hit route resolver domain
--- request
GET /hello
--- response_body
hello world
--- error_log_like eval
qr/http:\/\/test\.com is resolved to: http:\/\/((2(5[0-5]|[0-4]\d))|[0-1]?\d{1,2})(\.((2(5[0-5]|[0-4]\d))|[0-1]?\d{1,2})){3}/



=== TEST 25: set as a domain name that cannot be found.
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://not-find-domian.notfind",
                               "path": "/get"
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



=== TEST 26: hit route resolver error domain
--- request
GET /hello
--- response_body
hello world
--- error_log
dns resolver resolves domain: not-find-domian.notfind error:



=== TEST 27: custom path with prefix path_concat_mode
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986",
                               "path": "/a",
                               "path_concat_mode": "prefix"
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



=== TEST 28: hit route with prefix path_concat_mode
--- request
GET /hello
--- response_body
hello world
--- error_log
uri: /a/hello,



=== TEST 29: hit route with args and prefix path_concat_mode
--- request
GET /hello?a=1
--- response_body
hello world
--- error_log
uri: /a/hello?a=1



=== TEST 30: (grpc) sanity check (normal case grpc)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "grpc://127.0.0.1:1986"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "scheme": "grpc",
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
--- error_code: 200
--- response_body
passed



=== TEST 31: (grpcs) sanity check (normal case for grpcs)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "grpcs://127.0.0.1:1986"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "scheme": "grpc",
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
--- error_code: 200
--- response_body
passed
