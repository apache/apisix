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
        http: 'radixtree_uri_with_parameter'
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: set route
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
                    "uri": "/name/:name/bar"
                }]],
                [[{
                    "value": {
                        "uri": "/name/:name/bar",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                    },
                    "key": "/apisix/routes/1"
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



=== TEST 3: /name/json/foo
--- request
GET /name/json2/foo
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 4: /name/json/
--- request
GET /name/json/
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 5: /name//bar
--- request
GET /name//bar
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 6: hit route: /name/json/bar
--- request
GET /name/json/bar
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 7: set route，uri=/:name/foo
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
                    "uri": "/:name/foo"
                }]],
                [[{
                    "value": {
                        "uri": "/:name/foo",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                    },
                    "key": "/apisix/routes/1"
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



=== TEST 8: /json/foo
--- request
GET /json/foo
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 9: /json/bbb/foo
--- request
GET /json/bbb/foo
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 10: inherit hosts from services
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
                        "uri": "/:name/hello"
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
                        "plugins": {
                            "proxy-rewrite":{"uri":"/hello"}
                        },
                        "uri": "/:name/hello",
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



=== TEST 11: hit
--- more_headers
Host: www.foo.com
--- request
GET /john/hello
--- response_body
hello world
