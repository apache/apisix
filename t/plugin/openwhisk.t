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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity check with minimal valid configuration.
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk")
            local ok, err = plugin.check_schema({api_host = "http://127.0.0.1:3233", service_token = "test:test", namespace = "test", action = "test"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
Using openwhisk api_host with no TLS is a security risk



=== TEST 2: using https should not give security warning
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk")
            local ok, err = plugin.check_schema({api_host = "https://127.0.0.1:3233", service_token = "test:test", namespace = "test", action = "test"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
Using openwhisk api_host with no TLS is a security risk



=== TEST 3: missing `api_host`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk")
            local ok, err = plugin.check_schema({service_token = "test:test", namespace = "test", action = "test"})
            if not ok then
                ngx.say(err)
            end
        }
    }
--- response_body
property "api_host" is required



=== TEST 4: wrong type for `api_host`
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk")
            local ok, err = plugin.check_schema({api_host = 3233, service_token = "test:test", namespace = "test", action = "test"})
            if not ok then
                ngx.say(err)
            end
        }
    }
--- response_body
property "api_host" validation failed: wrong type: expected string, got number



=== TEST 5: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk": {
                                "api_host": "http://127.0.0.1:3233",
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
                                "namespace": "guest",
                                "action": "test-params"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- response_body
passed



=== TEST 6: verify encrypted field
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test


            -- get plugin conf from etcd, service_token is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["openwhisk"].service_token)

        }
    }
--- response_body
pe14btxogtzJ4qPM/W2qj0AQeUK/O5oegLkKJLkkSEsKUIjP+bgyO+qsTXuLrY/h/esLKrRulD2TOtf+Zt/Us+hxZ/svsMwXZqZ9T9/2wWyi8SKALLfTUZDiV69mxCwD2zNBze1jslMlPtdA9JFIOQ==



=== TEST 7: hit route (with GET request)
--- request
GET /hello
--- response_body chomp
{"hello":"test"}



=== TEST 8: hit route (with POST method and non-json format request body)
--- request
POST /hello
test=test
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- error_code: 400
--- response_body_like eval
qr/"error":"The request content was malformed/



=== TEST 9: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk": {
                                "api_host": "http://127.0.0.1:3233",
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
                                "namespace": "guest",
                                "action": "test-params"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- response_body
passed



=== TEST 10: hit route (with POST and correct request body)
--- request
POST /hello
{"name": "world"}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"hello":"world"}



=== TEST 11: reset route to non-existent action
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk": {
                                "api_host": "http://127.0.0.1:3233",
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
                                "namespace": "guest",
                                "action": "non-existent"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- response_body
passed



=== TEST 12: hit route (with non-existent action)
--- request
POST /hello
{"name": "world"}
--- more_headers
Content-Type: application/json
--- error_code: 404
--- response_body_like eval
qr/"error":"The requested resource does not exist."/



=== TEST 13: reset route to wrong api_host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk": {
                                "api_host": "http://127.0.0.1:1979",
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
                                "namespace": "guest",
                                "action": "non-existent"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- response_body
passed



=== TEST 14: hit route (with wrong api_host)
--- request
POST /hello
{"name": "world"}
--- more_headers
Content-Type: application/json
--- error_code: 503
--- error_log
failed to process openwhisk action, err:



=== TEST 15: reset route to packaged action
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk": {
                                "api_host": "http://127.0.0.1:3233",
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
                                "namespace": "guest",
                                "package": "pkg",
                                "action": "testpkg"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- response_body
passed



=== TEST 16: hit route (with packaged action)
--- request
GET /hello
--- response_body chomp
{"hello":"world"}



=== TEST 17: reset route to status code action
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk": {
                                "api_host": "http://127.0.0.1:3233",
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
                                "namespace": "guest",
                                "action": "test-statuscode"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- response_body
passed



=== TEST 18: hit route (with packaged action)
--- request
GET /hello
--- error_code: 407



=== TEST 19: reset route to headers action
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk": {
                                "api_host": "http://127.0.0.1:3233",
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
                                "namespace": "guest",
                                "action": "test-headers"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- response_body
passed



=== TEST 20: hit route (with headers action)
--- request
GET /hello
--- response_headers
test: header



=== TEST 21: reset route to body action
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "openwhisk": {
                                "api_host": "http://127.0.0.1:3233",
                                "service_token": "23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP",
                                "namespace": "guest",
                                "action": "test-body"
                            }
                        },
                        "upstream": {
                            "nodes": {},
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
--- response_body
passed



=== TEST 22: hit route (with body action)
--- request
GET /hello
--- response_body
{"test":"body"}
