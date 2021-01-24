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

    # for proxy cache
    proxy_cache_path /tmp/disk_cache_one levels=1:2 keys_zone=disk_cache_one:50m inactive=1d max_size=1G;
    proxy_cache_path /tmp/disk_cache_two levels=1:2 keys_zone=disk_cache_two:50m inactive=1d max_size=1G;

    # for proxy cache
    map \$upstream_cache_zone \$upstream_cache_zone_info {
        disk_cache_one /tmp/disk_cache_one,1:2;
        disk_cache_two /tmp/disk_cache_two,1:2;
    }

    server {
        listen 1986;
        server_tokens off;

        location / {
            expires 60s;
            return 200 "hello world!";
        }

        location /hello-not-found {
            return 404;
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: sanity check (missing cache_zone field, the default value is disk_cache_one)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": true,
                               "no_cache": ["$arg_no_cache"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                   }]],
                   [[{
                       "node": {
                        "value": {
                            "uri": "/hello",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "plugins": {
                                "proxy-cache":{
                                    "cache_zone":"disk_cache_one",
                                    "hide_cache_headers":true,
                                    "cache_bypass":["$arg_bypass"],
                                    "cache_key":["$host","$request_uri"],
                                    "no_cache":["$arg_no_cache"],
                                    "cache_http_status":[200],
                                    "cache_method":["GET"]
                                }
                            }
                        },
                        "key": "/apisix/routes/1"
                        },
                        "action": "set"
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
--- no_error_log
[error]



=== TEST 2: sanity check (invalid type for cache_method)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "disk_cache_one",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": "GET",
                               "cache_http_status": [200],
                               "hide_cache_headers": true,
                               "no_cache": ["$arg_no_cache"]
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
qr/failed to check the configuration of plugin proxy-cache/
--- no_error_log
[error]



=== TEST 3: sanity check (invalid type for cache_key)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "disk_cache_one",
                               "cache_key": "${uri}-cache-key",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": true,
                               "no_cache": ["$arg_no_cache"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1985": 1
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
qr/failed to check the configuration of plugin proxy-cache/
--- no_error_log
[error]



=== TEST 4: sanity check (invalid type for cache_bypass)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "disk_cache_one",
                               "cache_bypass": "$arg_bypass",
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": true,
                               "no_cache": ["$arg_no_cache"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1985": 1
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
qr/failed to check the configuration of plugin proxy-cache/
--- no_error_log
[error]



=== TEST 5: sanity check (invalid type for no_cache)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "disk_cache_one",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": true,
                               "no_cache": "$arg_no_cache"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1985": 1
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
qr/failed to check the configuration of plugin proxy-cache/
--- no_error_log
[error]



=== TEST 6: sanity check (illegal character for cache_key)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "disk_cache_one",
                               "cache_key": ["$uri-", "-cache-id"],
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": true,
                               "no_cache": ["$arg_no_cache"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1985": 1
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
qr/failed to check the configuration of plugin proxy-cache/
--- no_error_log
[error]



=== TEST 7: sanity check (normal case)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "disk_cache_one",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": true,
                               "no_cache": ["$arg_no_cache"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1986": 1
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: hit route (cache miss)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS
--- no_error_log
[error]



=== TEST 9: hit route (cache hit)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: HIT
--- raw_response_headers_unlike
Expires:
--- no_error_log
[error]



=== TEST 10: hit route (cache bypass)
--- request
GET /hello?bypass=1
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: BYPASS
--- no_error_log
[error]



=== TEST 11: purge cache
--- request
PURGE /hello
--- error_code: 200
--- no_error_log
[error]



=== TEST 12: hit route (nocache)
--- request
GET /hello?no_cache=1
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS
--- no_error_log
[error]



=== TEST 13: hit route (there's no cache indeed)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS
--- raw_response_headers_unlike
Expires:
--- no_error_log
[error]



=== TEST 14: hit route (will be cached)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: HIT
--- no_error_log
[error]



=== TEST 15: hit route (not found)
--- request
GET /hello-not-found
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- response_headers
Apisix-Cache-Status: MISS
--- no_error_log
[error]



=== TEST 16: hit route (404 there's no cache indeed)
--- request
GET /hello-not-found
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- response_headers
Apisix-Cache-Status: MISS
--- no_error_log
[error]



=== TEST 17: hit route (HEAD method)
--- request
HEAD /hello-world
--- error_code: 200
--- response_headers
Apisix-Cache-Status: MISS
--- no_error_log
[error]



=== TEST 18: hit route (HEAD method there's no cache)
--- request
HEAD /hello-world
--- error_code: 200
--- response_headers
Apisix-Cache-Status: MISS
--- no_error_log
[error]



=== TEST 19:  hide cache headers = false
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "disk_cache_one",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": false,
                               "no_cache": ["$arg_no_cache"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1986": 1
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 20: hit route (catch the cache headers)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: HIT
--- response_headers_like
Cache-Control:
--- no_error_log
[error]



=== TEST 21: purge cache
--- request
PURGE /hello
--- error_code: 200
--- no_error_log
[error]



=== TEST 22: purge cache (not found)
--- request
PURGE /hello-world
--- error_code: 404
--- no_error_log
[error]



=== TEST 23:  invalid cache zone
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "invalid_disk_cache",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": false,
                               "no_cache": ["$arg_no_cache"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1986": 1
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
--- error_code: 400
--- response_body eval
qr/cache_zone invalid_disk_cache not found/
--- no_error_log
[error]



=== TEST 24: sanity check (invalid variable for cache_key)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_zone": "disk_cache_one",
                               "cache_key": ["$uri", "$request_method"],
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_http_status": [200],
                               "hide_cache_headers": true,
                               "no_cache": ["$arg_no_cache"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1985": 1
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
qr/failed to check the configuration of plugin proxy-cache err: cache_key variable \$request_method unsupported/
--- no_error_log
[error]
