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
                        "host": "*.foo.com",
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



=== TEST 4: /not_found
--- request
GET /hello
--- more_headers
Host: not_found.com
--- error_code: 404



=== TEST 5: hit routes (www.foo.com)
--- request
GET /hello
--- more_headers
Host: www.foo.com
--- response_body
hello world



=== TEST 6: hit routes (user.foo.com)
--- request
GET /hello
--- more_headers
Host: user.foo.com
--- response_body
hello world



=== TEST 7: set route(id: 1)
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



=== TEST 8: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 9: /not_found
--- request
GET /hello
--- error_code: 404



=== TEST 10: /not_found
--- request
GET /hello
--- more_headers
Host: www.foo.com
--- error_code: 404



=== TEST 11: hit routes (foo.com)
--- request
GET /hello
--- more_headers
Host: foo.com
--- response_body
hello world



=== TEST 12: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "filter_func": "function(vars) return vars.arg_name == 'json' end",
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



=== TEST 13: not hit: name=unknown
--- request
GET /hello?name=unknown
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 14: hit routes
--- request
GET /hello?name=json
--- response_body
hello world



=== TEST 15: set route with ':'
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/file:listReputationHistories",
                    "plugins":{"proxy-rewrite":{"uri":"/hello"}},
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



=== TEST 16: hit routes
--- request
GET /file:listReputationHistories
--- response_body
hello world



=== TEST 17: not hit
--- request
GET /file:xx
--- error_code: 404



=== TEST 18: inherit hosts from services
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "hosts": ["bar.com"]
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

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
                        "plugins": {
                            "proxy-rewrite":{"uri":"/hello1"}
                        },
                        "service_id": "1",
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "priority": -1
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



=== TEST 19: hit
--- more_headers
Host: www.foo.com
--- request
GET /hello
--- response_body
hello world



=== TEST 20: change hosts in services
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "hosts": ["foo.com"]
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {headers = {Host = "foo.com"}})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)

            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "hosts": ["bar.com"]
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {headers = {Host = "foo.com"}})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- response_body
hello1 world
hello world



=== TEST 21: unbind services
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
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
                        "plugins": {
                            "proxy-rewrite":{"uri":"/hello1"}
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {headers = {Host = "foo.com"}})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- response_body
hello1 world



=== TEST 22: host from route is preferred
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
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
                        "hosts": ["foo.com"],
                        "plugins": {
                            "proxy-rewrite":{"uri":"/hello1"}
                        },
                        "service_id": "1",
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            for _, h in ipairs({"foo.com", "bar.com"}) do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {headers = {Host = h}})
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.print(res.body)
            end

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
                        "plugins": {
                            "proxy-rewrite":{"uri":"/hello1"}
                        },
                        "service_id": "1",
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            for _, h in ipairs({"foo.com", "bar.com"}) do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {headers = {Host = h}})
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.print(res.body)
            end
        }
    }
--- request
GET /t
--- response_body
hello1 world
hello world
hello1 world
hello world
