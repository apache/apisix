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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
log_level('info');
run_tests;

__DATA__

=== TEST 1: sanity check (missing required field)
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
                               "cache_key": ["$uri"],
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
                               "cache_key": ["$uri", "-cache-id"],
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
                               "cache_key": ["$uri", "-cache-id"],
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
                               "cache_key": ["$uri", "-cache-id"],
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]
