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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 11451;
        gzip on;
        gzip_types *;
        gzip_min_length 1;
        location /gzip_hello {
            content_by_lua_block {
                ngx.req.read_body()
                local s = "hello world"
                ngx.header['Content-Length'] = #s + 1
                ngx.say(s)
            }
        }
        location /gzip_empty {
            content_by_lua_block {
                ngx.header['Content-Encoding'] = "gzip"
                ngx.header['Content-Length'] = 0
                ngx.send_headers()
            }
        }
    }

    server {
        listen 11452;
        location /brotli_hello {
            content_by_lua_block {
                ngx.req.read_body()
                local s = "hello world hello world hello world"
                ngx.header['Content-Length'] = #s + 1
                ngx.say(s)
            }
            header_filter_by_lua_block {
                local conf = {
                    comp_level = 6,
                    http_version = 1.1,
                    lgblock = 0,
                    lgwin = 19,
                    min_length = 1,
                    mode = 0,
                    types = "*",
                }
                local brotli = require("apisix.plugins.brotli")
                brotli.header_filter(conf, ngx.ctx)
            }
            body_filter_by_lua_block {
                local conf = {
                    comp_level = 6,
                    http_version = 1.1,
                    lgblock = 0,
                    lgwin = 19,
                    min_length = 1,
                    mode = 0,
                    types = "*",
                }
                local brotli = require("apisix.plugins.brotli")
                brotli.body_filter(conf, ngx.ctx)
            }
        }
    }

    server {
        listen 11453;
        location / {
            content_by_lua_block {
                local wire = ngx.decode_base64("jwWAaGVsbG8gYnJvdGxpAw==")
                ngx.header["Content-Encoding"] = "br"
                ngx.header["Content-Length"] = #wire
                ngx.header["ETag"] = '"origin"'
                ngx.header["X-Accel-Buffering"] = "no"
                ngx.print(wire:sub(1, 6))
                ngx.flush(true)
                ngx.sleep(0.05)
                ngx.print(wire:sub(7))
            }
        }
    }

_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: set route use gzip upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
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



=== TEST 2: should return gzip body
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- response_headers
Content-Encoding: gzip



=== TEST 3: set route use gzip upstream and response-rewrite body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "body": "new body\n"
                        }
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



=== TEST 4: should rewrite body and clear Content-Encoding header
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- response_body
new body
--- response_headers
Content-Encoding:



=== TEST 5: set route use gzip upstream and response-rewrite filter conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "test"
                                }
                            ]
                        }
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



=== TEST 6: gzip decode support, should rewrite body and clear Content-Encoding header
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- response_body
test world
--- response_headers
Content-Encoding:



=== TEST 7: set route use response-write body conf, and mock unsupported compression encoding type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "body": "new body\n"
                        }
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



=== TEST 8: use body conf will ignore encoding, should rewrite body and clear Content-Encoding header
--- request
POST /echo
fake body with mock content encoding header
--- more_headers
Content-Encoding: deflate
--- response_body
new body
--- response_headers
Content-Encoding:



=== TEST 9: set route use response-write filter conf, and mock unsupported compression encoding type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "test"
                                }
                            ]
                        }
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



=== TEST 10: use filter conf will report unsupported encoding type error
--- request
POST /echo
fake body with mock content encoding header
--- more_headers
Content-Encoding: deflate
--- response_headers
Content-Encoding:
--- error_log
filters may not work as expected due to unsupported compression encoding type: deflate



=== TEST 11: set route use response-write plugin but not use filter conf or body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "headers": {
                                "set": {
                                    "X-Server-id": 3,
                                    "X-Server-status": "on",
                                    "Content-Type": ""
                                }
                            }
                        }
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



=== TEST 12: should keep Content-Encoding
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- response_headers
Content-Encoding: gzip
X-Server-id: 3
X-Server-status: on
Content-Type:



=== TEST 13: response-write without filter conf or body conf, and mock unsupported compression encoding type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "headers": {
                                "set": {
                                    "X-Server-id": 3,
                                    "X-Server-status": "on",
                                    "Content-Type": ""
                                }
                            }
                        }
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



=== TEST 14: should keep Content-Encoding
--- request
POST /echo
fake body with mock content encoding header
--- more_headers
Content-Encoding: deflate
--- response_headers
Content-Encoding: deflate
X-Server-id: 3
X-Server-status: on
Content-Type:



=== TEST 15: set route use brotli upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/brotli_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11452": 1
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



=== TEST 16: should return brotli body
--- request
GET /brotli_hello
--- more_headers
Accept-Encoding: br
--- response_headers
Content-Encoding: br



=== TEST 17: set route use brotli upstream and response-rewrite body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/brotli_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11452": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "body": "new body\n"
                        }
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



=== TEST 18: should rewrite body and clear Content-Encoding header
--- request
GET /brotli_hello
--- more_headers
Accept-Encoding: br
--- response_body
new body
--- response_headers
Content-Encoding:



=== TEST 19: set route use brotli upstream and response-rewrite filter conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/brotli_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11452": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "test"
                                }
                            ]
                        }
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



=== TEST 20: brotli decode support, should rewrite body and clear Content-Encoding header
--- request
GET /brotli_hello
--- more_headers
Accept-Encoding: br
--- response_body
test world hello world hello world
--- response_headers
Content-Encoding:



=== TEST 21: set route use response-write plugin but not use filter conf or body conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/brotli_hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11452": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "vars": [
                                ["status","==",200]
                            ],
                            "headers": {
                                "set": {
                                    "X-Server-id": 3,
                                    "X-Server-status": "on",
                                    "Content-Type": ""
                                }
                            }
                        }
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



=== TEST 22: should keep Content-Encoding
--- request
GET /brotli_hello
--- more_headers
Accept-Encoding: br
--- response_headers
Content-Encoding: br
X-Server-id: 3
X-Server-status: on
Content-Type:



=== TEST 23: set route with filters to an upstream sending an empty gzip body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/gzip_empty",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:11451": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "response-rewrite": {
                            "filters": [
                                {
                                    "regex": "hello",
                                    "replace": "test"
                                }
                            ]
                        }
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



=== TEST 24: an empty gzip body is passed through without a decode error
--- request
GET /gzip_empty
--- response_body
--- response_headers
Content-Encoding:
--- no_error_log
filters may not work as expected



=== TEST 25: unavailable br decoder passes chunks through and still applies independent rewrites
--- extra_init_by_lua_start
    package.preload["resty.brotli"] = function()
        error("libbrotlidec.so.1 unavailable", 0)
    end
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, mode in ipairs({"filtered", "fixed"}) do
                local rewrite = {status_code = 202, headers = {["X-Rewrite"] = mode}}
                if mode == "filtered" then
                    rewrite.filters = {{regex = "hello", replace = "new"}}
                else
                    rewrite.body = "replacement"
                end
                local status = t("/apisix/admin/routes/" .. mode, ngx.HTTP_PUT, {
                    uri = "/" .. mode,
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:11453"] = 1}},
                    plugins = {["response-rewrite"] = rewrite},
                })
                assert(status < 300)
            end
            for i = 1, 2 do
                local status, _, wire, h = t("/filtered", ngx.HTTP_GET)
                ngx.say(status, " ", h["X-Rewrite"], " ", h["Content-Encoding"], " ",
                        h["Content-Length"], " ", h["ETag"], " ", ngx.encode_base64(wire))
            end
            local status, _, body, h = t("/fixed", ngx.HTTP_GET)
            ngx.say(status, " ", h["X-Rewrite"], " ", h["Content-Encoding"], " ", body)
        }
    }
--- response_body
202 filtered br 16 "origin" jwWAaGVsbG8gYnJvdGxpAw==
202 filtered br 16 "origin" jwWAaGVsbG8gYnJvdGxpAw==
202 fixed nil replacement
--- grep_error_log eval
qr/failed to load resty\.brotli: libbrotlidec\.so\.1 unavailable/
--- grep_error_log_out
failed to load resty.brotli: libbrotlidec.so.1 unavailable



=== TEST 26: available br decoder rewrites the complete multi-chunk response
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local status, _, body, h = t("/filtered", ngx.HTTP_GET)
            ngx.say(status, " ", h["X-Rewrite"], " ", h["Content-Encoding"], " ", body)
        }
    }
--- response_body
202 filtered nil new brotli
