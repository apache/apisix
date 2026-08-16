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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // "";
    $http_config .= <<_EOC_;
lua_shared_dict query-gateway-cache 32m;

server {
    listen 1986;

    location = /query-gateway-method {
        content_by_lua_block {
            ngx.say("method: ", ngx.req.get_method())
            ngx.say("x-original-method: ",
                    ngx.req.get_headers()["x-original-method"])
        }
    }

    location = /query-cache {
        content_by_lua_block {
            local value = ngx.shared["query-gateway-cache"]:incr("test-counter", 1, 0)
            ngx.say("method: ", ngx.req.get_method())
            ngx.say("counter: ", value)
        }
    }

    location = /query-cache-no-store {
        content_by_lua_block {
            ngx.header["Cache-Control"] = "no-store"
            local value = ngx.shared["query-gateway-cache"]:incr("no-store-counter", 1, 0)
            ngx.say("counter: ", value)
        }
    }

    location = /echo {
        content_by_lua_block {
            ngx.req.read_body()
            ngx.print(ngx.req.get_body_data() or "")
        }
    }
}
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: validate plugin schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.query-gateway")
            local ok, err = plugin.check_schema({
                original_method_header = "X-Original-Method",
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: reject an invalid original method header
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.query-gateway")
            local ok, err = plugin.check_schema({
                original_method_header = "Bad:Header",
            })
            ngx.say(ok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/false
invalid original_method_header/



=== TEST 3: add a QUERY route
--- upstream_server_config
        location = /query-gateway-method {
            content_by_lua_block {
                ngx.say("method: ", ngx.req.get_method())
                ngx.say("x-original-method: ",
                        ngx.req.get_headers()["x-original-method"])
            }
        }
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                    "vars": [["request_method", "==", "QUERY"]],
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/query-gateway-method"
                        },
                        "query-gateway": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1986": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/query-gateway"
                }]=]
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



=== TEST 4: transform QUERY to POST and preserve the original method
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway
--- response_body
method: POST
x-original-method: QUERY



=== TEST 5: update route to forward the request body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                    "vars": [["request_method", "==", "QUERY"]],
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/echo"
                        },
                        "query-gateway": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1986": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/query-gateway/body"
                }]=]
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



=== TEST 6: preserve QUERY request body
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway/body
{"query":"apisix"}
--- response_body_like eval
qr/{"query":"apisix"}/



=== TEST 7: reject a QUERY without Content-Type even when cache is disabled
--- request
QUERY /query-gateway/body
{"query":"missing-type"}
--- error_code: 400



=== TEST 8: do not match POST on a QUERY-only route
--- request
POST /query-gateway/body
{"query":"apisix"}
--- error_code: 404



=== TEST 9: reject incomplete Redis cache configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.query-gateway")
            local ok, err = plugin.check_schema({
                cache = {
                    enabled = true,
                    backend = "redis",
                },
            })
            ngx.say(ok)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/false
cache.redis_host is required/



=== TEST 10: add a body-aware QUERY cache route
--- upstream_server_config
        location = /query-cache {
            content_by_lua_block {
                local value = ngx.shared["query-gateway-cache"]:incr("test-counter", 1, 0)
                ngx.say("method: ", ngx.req.get_method())
                ngx.say("counter: ", value)
            }
        }
--- config
    location /t {
        content_by_lua_block {
            ngx.shared["query-gateway-cache"]:delete("test-counter")

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [=[{
                    "vars": [["request_method", "==", "QUERY"]],
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/query-cache"
                        },
                        "query-gateway": {
                            "cache": {
                                "enabled": true,
                                "backend": "local",
                                "ttl": 30,
                                "max_request_body_size": 1024,
                                "max_response_body_size": 1024
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1986": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/query-gateway/cache"
                }]=]
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



=== TEST 11: store a QUERY response under its request body digest
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway/cache
{"query":"one"}
--- response_body
method: POST
counter: 1
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 12: serve the same QUERY body from the local cache
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway/cache
{"query":"one"}
--- response_body
method: POST
counter: 1
--- response_headers
Apisix-Cache-Status: HIT



=== TEST 13: do not collide cache entries for different QUERY bodies
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway/cache
{"query":"two"}
--- response_body
method: POST
counter: 2
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 14: bypass cache for a request cookie
--- more_headers
Content-Type: application/json
Cookie: session=private
--- request
QUERY /query-gateway/cache
{"query":"one"}
--- response_body
method: POST
counter: 3



=== TEST 15: reject a cacheable QUERY without Content-Type
--- request
QUERY /query-gateway/cache
{"query":"missing-type"}
--- error_code: 400



=== TEST 16: add a route that preserves QUERY for a native QUERY upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_PUT,
                 [=[{
                    "vars": [["request_method", "==", "QUERY"]],
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/query-gateway-method"
                        },
                        "query-gateway": {
                            "query": {
                                "upstream_method": "query"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1986": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/query-gateway/native"
                }]=]
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



=== TEST 17: preserve QUERY when the upstream supports it
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway/native
--- response_body
method: QUERY
x-original-method: QUERY



=== TEST 18: add a route that accepts an existing POST query
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/4',
                 ngx.HTTP_PUT,
                 [=[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/query-gateway-method"
                        },
                        "query-gateway": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1986": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/query-gateway/post"
                }]=]
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



=== TEST 19: preserve an existing POST request
--- request
POST /query-gateway/post
{"query":"apisix"}
--- response_body
method: POST
x-original-method: nil



=== TEST 20: add a route that shares explicit read-only POST and QUERY cache entries
--- config
    location /t {
        content_by_lua_block {
            ngx.shared["query-gateway-cache"]:delete("test-counter")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/5',
                 ngx.HTTP_PUT,
                 [=[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/query-cache"
                        },
                        "query-gateway": {
                            "post": {
                                "cache_enabled": true,
                                "read_only": true
                            },
                            "cache": {
                                "enabled": true,
                                "backend": "local",
                                "ttl": 30,
                                "max_request_body_size": 1024,
                                "max_response_body_size": 1024
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1986": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/query-gateway/shared"
                }]=]
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



=== TEST 21: store a QUERY response for an explicit read-only POST route
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway/shared
{"query":"shared"}
--- response_body
method: POST
counter: 1
--- response_headers
Apisix-Cache-Status: MISS



=== TEST 22: serve an equivalent explicit read-only POST from the QUERY cache entry
--- more_headers
Content-Type: application/json
--- request
POST /query-gateway/shared
{"query":"shared"}
--- response_body
method: POST
counter: 1
--- response_headers
Apisix-Cache-Status: HIT
Age: 0



=== TEST 23: bypass cache when the client requests no-store
--- more_headers
Content-Type: application/json
Cache-Control: no-store
--- request
QUERY /query-gateway/cache
{"query":"one"}
--- response_body
method: POST
counter: 2



=== TEST 24: bypass cache for conditional QUERY requests
--- more_headers
Content-Type: application/json
If-None-Match: "query-v1"
--- request
QUERY /query-gateway/cache
{"query":"one"}
--- response_body
method: POST
counter: 3



=== TEST 25: add a no-store upstream route
--- config
    location /t {
        content_by_lua_block {
            ngx.shared["query-gateway-cache"]:delete("no-store-counter")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/6',
                 ngx.HTTP_PUT,
                 [=[{
                    "vars": [["request_method", "==", "QUERY"]],
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/query-cache-no-store"
                        },
                        "query-gateway": {
                            "cache": {
                                "enabled": true,
                                "backend": "local",
                                "ttl": 30
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1986": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/query-gateway/no-store"
                }]=]
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



=== TEST 26: do not store a no-store upstream response
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway/no-store
{"query":"one"}
--- response_body
counter: 1



=== TEST 27: do not serve a no-store upstream response from cache
--- more_headers
Content-Type: application/json
--- request
QUERY /query-gateway/no-store
{"query":"one"}
--- response_body
counter: 2
