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

                core.log.info("uri: ", ngx.var.uri)
                ngx.say("hello world")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
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
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-mirror/
--- no_error_log
[error]



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
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-mirror/
--- no_error_log
[error]



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
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-mirror/
--- no_error_log
[error]



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
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



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
--- request
GET /t
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-mirror/
--- no_error_log
[error]



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
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



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
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



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
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



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
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]
