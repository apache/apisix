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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: ~
    admin_api_version: v3
apisix:
    node_listen: 1984
_EOC_
    $block->set_value("yaml_config", $user_yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: use v3 admin api, no action in response body
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
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]],
                [[{
                    "value": {
                        "methods": [
                            "GET"
                        ],
                        "uri": "/index.html",
                        "desc": "new route",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        }
                    },
                    "key": "/apisix/routes/1"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: response body format only have total and list (total is 1)
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/routes', ngx.HTTP_GET)

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            res = json.decode(res)
            assert(res.total == 1)
            assert(res.total == #res.list)
            assert(res.action == nil)
            assert(res.node == nil)
            assert(res.list.key == nil)
            assert(res.list.dir == nil)
            assert(res.list[1].createdIndex ~= nil)
            assert(res.list[1].modifiedIndex ~= nil)
            assert(res.list[1].key == "/apisix/routes/1")
            ngx.say(message)
        }
    }
--- response_body
passed



=== TEST 3: response body format only have total and list (total is 2)
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            local code, message, res = t('/apisix/admin/routes',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            assert(res.total == 2)
            assert(res.total == #res.list)
            assert(res.action == nil)
            assert(res.node == nil)
            assert(res.list.key == nil)
            assert(res.list.dir == nil)
            assert(res.list[1].createdIndex ~= nil)
            assert(res.list[1].modifiedIndex ~= nil)
            assert(res.list[1].key == "/apisix/routes/1")
            assert(res.list[2].createdIndex ~= nil)
            assert(res.list[2].modifiedIndex ~= nil)
            assert(res.list[2].key == "/apisix/routes/2")
            ngx.say(message)
        }
    }
--- response_body
passed



=== TEST 4: response body format (test services)
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new service 001"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            local code, body = t('/apisix/admin/services/2',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new service 002"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            local code, message, res = t('/apisix/admin/services', ngx.HTTP_GET)

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            assert(res.total == 2)
            assert(res.total == #res.list)
            assert(res.action == nil)
            assert(res.node == nil)
            assert(res.list.key == nil)
            assert(res.list.dir == nil)
            assert(res.list[1].createdIndex ~= nil)
            assert(res.list[1].modifiedIndex ~= nil)
            assert(res.list[1].key == "/apisix/services/1")
            assert(res.list[2].createdIndex ~= nil)
            assert(res.list[2].modifiedIndex ~= nil)
            assert(res.list[2].key == "/apisix/services/2")
            ngx.say(message)
        }
    }
--- response_body
passed
passed
passed
