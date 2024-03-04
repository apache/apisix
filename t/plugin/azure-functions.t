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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $inside_lua_block = $block->inside_lua_block // "";
    chomp($inside_lua_block);
    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 8765;

        location /httptrigger {
            content_by_lua_block {
                ngx.req.read_body()
                local msg = "faas invoked"
                ngx.header['Content-Length'] = #msg + 1
                ngx.header['X-Extra-Header'] = "MUST"
                ngx.header['Connection'] = "Keep-Alive"
                ngx.say(msg)
            }
        }

        location  /api {
           content_by_lua_block {
                ngx.say("invocation /api successful")
            }
        }

        location /api/httptrigger {
           content_by_lua_block {
                ngx.say("invocation /api/httptrigger successful")
            }
        }

        location /api/http/trigger {
           content_by_lua_block {
                ngx.say("invocation /api/http/trigger successful")
            }
        }

        location /azure-demo {
            content_by_lua_block {
                $inside_lua_block
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.azure-functions")
            local conf = {
                function_uri = "http://some-url.com"
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: function_uri missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.azure-functions")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
property "function_uri" is required



=== TEST 3: create route with azure-function plugin enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "azure-functions": {
                                "function_uri": "http://localhost:8765/httptrigger"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/azure"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: Test plugin endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")

            local code, _, body, headers = t("/azure", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- headers proxied 2 times -- one by plugin, another by this test case
            core.response.set_header(headers)
            ngx.print(body)
        }
    }
--- response_body
faas invoked
--- response_headers
Content-Length: 13
X-Extra-Header: MUST



=== TEST 5: http2 check response body and headers
--- http2
--- request
GET /azure
--- more_headers
Content-Length: 0
--- response_body
faas invoked



=== TEST 6: check HTTP/2 response headers (must not contain any connection specific info)
First fetch the header from curl with -I then check the count of Connection
The full header looks like the format shown below

HTTP/2 200
content-type: text/plain
x-extra-header: MUST
content-length: 13
date: Wed, 17 Nov 2021 13:53:08 GMT
server: APISIX/2.10.2

--- http2
--- request
HEAD /azure
--- more_headers
Content-Length: 0
--- response_headers
Connection:
Upgrade:
Keep-Alive:
content-type: text/plain
x-extra-header: MUST
content-length: 13



=== TEST 7: check authz header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- passing an apikey
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "azure-functions": {
                                "function_uri": "http://localhost:8765/azure-demo",
                                "authorization": {
                                    "apikey": "test_key"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/azure"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            local code, _, body = t("/azure", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- inside_lua_block
local headers = ngx.req.get_headers() or {}
ngx.say("Authz-Header - " .. headers["x-functions-key"] or "")

--- response_body
passed
Authz-Header - test_key



=== TEST 8: check if apikey doesn't get overridden passed by client to the gateway
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local header = {}
            header["x-functions-key"] = "must_not_be_overrided"

            -- plugin schema already contains apikey with value "test_key" which won't be respected
            local code, _, body = t("/azure", "GET", nil, nil, header)
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.print(body)
        }
    }
--- inside_lua_block
local headers = ngx.req.get_headers() or {}
ngx.say("Authz-Header - " .. headers["x-functions-key"] or "")

--- response_body
Authz-Header - must_not_be_overrided



=== TEST 9: fall back to metadata master key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, meta_body = t('/apisix/admin/plugin_metadata/azure-functions',
                ngx.HTTP_PUT,
                [[{
                    "master_apikey":"metadata_key"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(meta_body)

            -- update plugin attribute
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "azure-functions": {
                                "function_uri": "http://localhost:8765/azure-demo"
                            }
                        },
                        "uri": "/azure"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            -- plugin schema already contains apikey with value "test_key" which won't be respected
            local code, _, body = t("/azure", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.print(body)
        }
    }
--- inside_lua_block
local headers = ngx.req.get_headers() or {}
ngx.say("Authz-Header - " .. headers["x-functions-key"] or "")

--- response_body
passed
passed
Authz-Header - metadata_key



=== TEST 10: check if url path being forwarded correctly by creating a semi correct path uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- creating a semi path route
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "azure-functions": {
                                "function_uri": "http://localhost:8765/api"
                            }
                        },
                        "uri": "/azure/*"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            local code, _, body = t("/azure/httptrigger", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- response_body
passed
invocation /api/httptrigger successful



=== TEST 11: check multilevel url path forwarding
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, _, body = t("/azure/http/trigger", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- response_body
invocation /api/http/trigger successful



=== TEST 12: check url path forwarding containing multiple slashes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, _, body = t("/azure///http////trigger", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- response_body
invocation /api/http/trigger successful



=== TEST 13: check url path forwarding with no excess path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, _, body = t("/azure/", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- response_body
invocation /api successful



=== TEST 14: create route with azure-function plugin enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "azure-functions": {
                                "function_uri": "http://localhost:8765/httptrigger"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/azure"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: http2 failed to check response body and headers
--- http2
--- request
GET /azure
--- error_code: 400
--- error_log
HTTP2/HTTP3 request without a Content-Length header,
