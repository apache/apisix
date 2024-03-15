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
BEGIN {
    $ENV{TEST_NGINX_FORCE_RESTART_ON_TEST} = 0;
}

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
    lua_shared_dict memory_cache 50m;

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

            if (\$arg_expires) {
                expires \$arg_expires;
            }

            if (\$arg_cc) {
                expires off;
                add_header Cache-Control \$arg_cc;
            }

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

=== TEST 1: sanity check (invalid cache strategy)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_strategy": "network",
                               "cache_key":["$host","$uri"],
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
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-cache err: property \\"cache_strategy\\" validation failed: matches none of the enum values/



=== TEST 2: sanity check (invalid cache_zone when specifying cache_strategy as memory)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_strategy": "memory",
                               "cache_key":["$host","$uri"],
                               "cache_zone": "invalid_cache_zone",
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
--- error_code: 400
--- response_body eval
qr/failed to check the configuration of plugin proxy-cache err: cache_zone invalid_cache_zone not found"/



=== TEST 3: sanity check (normal case for memory strategy)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_strategy": "memory",
                               "cache_key":["$host","$uri"],
                               "cache_zone": "memory_cache",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "hide_cache_headers": false,
                               "cache_ttl": 300,
                               "cache_http_status": [200],
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



=== TEST 4: hit route (cache miss)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 5: hit route (cache hit)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: HIT



=== TEST 6: hit route (cache bypass)
--- request
GET /hello?bypass=1
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: BYPASS



=== TEST 7: purge cache
--- request
PURGE /hello
--- error_code: 200



=== TEST 8: hit route (nocache)
--- request
GET /hello?no_cache=1
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 9: hit route (there's no cache indeed)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS
--- raw_response_headers_unlike
Expires:



=== TEST 10: hit route (will be cached)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: HIT



=== TEST 11: hit route (not found)
--- request
GET /hello-not-found
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 12: hit route (404 there's no cache indeed)
--- request
GET /hello-not-found
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 13: hit route (HEAD method)
--- request
HEAD /hello-world
--- error_code: 200
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 14: hit route (HEAD method there's no cache)
--- request
HEAD /hello-world
--- error_code: 200
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 15: purge cache
--- request
PURGE /hello
--- error_code: 200



=== TEST 16: purge cache (not found)
--- request
PURGE /hello-world
--- error_code: 404



=== TEST 17:  hide cache headers = false
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_strategy": "memory",
                               "cache_key":["$host","$uri"],
                               "cache_zone": "memory_cache",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_ttl": 300,
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



=== TEST 18: hit route (catch the cache headers)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS
--- response_headers_like
Cache-Control:



=== TEST 19: don't override cache relative headers
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
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



=== TEST 20: hit route
--- request
GET /echo
--- more_headers
Apisix-Cache-Status: Foo
Cache-Control: bar
Expires: any
--- response_headers
Apisix-Cache-Status: Foo
Cache-Control: bar
Expires: any



=== TEST 21:  set cache_ttl to 1
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_strategy": "memory",
                               "cache_key":["$host","$uri"],
                               "cache_zone": "memory_cache",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_method": ["GET"],
                               "cache_ttl": 2,
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



=== TEST 22: hit route (MISS)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 23: hit route (HIT)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: HIT
--- wait: 2



=== TEST 24: hit route (MISS)
--- request
GET /hello
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: EXPIRED



=== TEST 25:  enable cache_control option
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_strategy": "memory",
                               "cache_key":["$host","$uri"],
                               "cache_zone": "memory_cache",
                               "cache_bypass": ["$arg_bypass"],
                               "cache_control": true,
                               "cache_method": ["GET"],
                               "cache_ttl": 10,
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



=== TEST 26: hit route (MISS)
--- request
GET /hello
--- more_headers
Cache-Control: max-age=60
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS
--- wait: 1



=== TEST 27: hit route (request header cache-control with max-age)
--- request
GET /hello
--- more_headers
Cache-Control: max-age=1
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: STALE



=== TEST 28: hit route  (request header cache-control with min-fresh)
--- request
GET /hello
--- more_headers
Cache-Control: min-fresh=300
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: STALE
--- wait: 1



=== TEST 29: purge cache
--- request
PURGE /hello
--- error_code: 200



=== TEST 30: hit route  (request header cache-control with no-store)
--- request
GET /hello
--- more_headers
Cache-Control: no-store
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: BYPASS



=== TEST 31: hit route  (request header cache-control with no-cache)
--- request
GET /hello
--- more_headers
Cache-Control: no-cache
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: BYPASS



=== TEST 32: hit route  (response header cache-control with private)
--- request
GET /hello?cc=private
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 33: hit route  (response header cache-control with no-store)
--- request
GET /hello?cc=no-store
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 34: hit route  (response header cache-control with no-cache)
--- request
GET /hello?cc=no-cache
--- response_body chop
hello world!
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 35: hit route  (request header cache-control with only-if-cached)
--- request
GET /hello
--- more_headers
Cache-Control: only-if-cached
--- error_code: 504



=== TEST 36: configure plugin without memory_cache zone for cache_strategy = memory
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-cache": {
                               "cache_strategy": "memory",
                               "cache_key":["$host","$uri"],
                               "cache_bypass": ["$arg_bypass"],
                               "cache_control": true,
                               "cache_method": ["GET"],
                               "cache_ttl": 10,
                               "cache_http_status": [200]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1986": 1
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
--- response_body_like
.*err: invalid or empty cache_zone for cache_strategy: memory.*
--- error_code: 400
