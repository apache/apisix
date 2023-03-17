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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

our $servlet_yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri'
    normalize_uri_like_servlet: true
_EOC_

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri'
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "host": "foo.com",
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
--- response_body
passed



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 3: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 4: /not_found
--- request
GET /hello
--- more_headers
Host: not_found.com
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 5: hit routes
--- request
GET /hello
--- more_headers
Host: foo.com
--- response_body
hello world



=== TEST 6: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1981": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/server_port"
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



=== TEST 7: /not_found
--- request
GET /hello
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 8: hit routes
--- request
GET /server_port
--- more_headers
Host: anydomain.com
--- response_body_like eval
qr/1981/



=== TEST 9: set route(id: 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1981": 1
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
--- response_body
passed



=== TEST 10: /not_found
--- request
GET /hello2
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 11: hit routes
--- request
GET /hello
--- more_headers
Host: anydomain.com
--- response_body
hello world



=== TEST 12: delete route(id: 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_DELETE
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



=== TEST 13: set route(id: 1)
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
--- response_body
passed



=== TEST 14: hit route with /hello
--- request
GET /hello
--- response_body
hello world



=== TEST 15: miss route
--- request
GET /hello/
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 16: match route like servlet
--- yaml_config eval: $::servlet_yaml_config
--- request
GET /hello;world
--- response_body eval
qr/404 Not Found/
--- error_code: 404



=== TEST 17: plugin should work on the normalized url
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
                        "uri": "/*",
                        "plugins": {
                            "uri-blocker": {
                                "block_rules": ["/hello/world"]
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



=== TEST 18: hit
--- yaml_config eval: $::servlet_yaml_config
--- request
GET /hello;a=b/world;a/;
--- error_code: 403



=== TEST 19: reject bad uri
--- yaml_config eval: $::servlet_yaml_config
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            for _, path in ipairs({
                "/;/a", "/%2e;", "/%2E%2E;", "/.;", "/..;",
                "/%2E%2e;", "/b/;/c"
            }) do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri .. path)
                if not res then
                    ngx.say(err)
                    return
                end

                if res.status ~= 400 then
                    ngx.say(path, " ", res.status)
                end
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- error_log
failed to normalize
