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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: update the nameserver_list, generate different rocketmq producers
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
            ngx.sleep(0.5)

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            code, body = t('/apisix/admin/routes/1/plugins',
                ngx.HTTP_PATCH,
                 [[{
                        "rocketmq-logger": {
                            "nameserver_list" : [ "127.0.0.1:9876" ],
                            "topic" : "test2",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)

            code, body = t('/apisix/admin/routes/1/plugins',
                ngx.HTTP_PATCH,
                 [[{
                        "rocketmq-logger": {
                            "nameserver_list" :  [ "127.0.0.1:19876" ],
                            "topic" : "test4",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)

            ngx.sleep(2)
            ngx.say("passed")
        }
    }
--- timeout: 10
--- response
passed
--- wait: 5
--- error_log
phase_func(): rocketmq nameserver_list[1] port 9876
phase_func(): rocketmq nameserver_list[1] port 19876
--- no_error_log eval
qr/not found topic/



=== TEST 2: use the topic that does not exist on rocketmq(even if rocketmq allows auto create topics, first time push messages to rocketmq would got this error)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1/plugins',
                ngx.HTTP_PATCH,
                 [[{
                        "rocketmq-logger": {
                            "nameserver_list" : [ "127.0.0.1:9876" ],
                            "topic" : "undefined_topic",
                            "timeout" : 1,
                            "batch_max_size": 1,
                            "include_req_body": false
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            t('/hello',ngx.HTTP_GET)
            ngx.sleep(0.5)

            ngx.sleep(2)
            ngx.say("passed")
        }
    }
--- timeout: 5
--- response
passed
--- error_log eval
qr/getTopicRouteInfoFromNameserver return TOPIC_NOT_EXIST, No topic route info in name server for the topic: undefined_topic/



=== TEST 3: rocketmq nameserver list info in log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                             "rocketmq-logger": {
                                    "nameserver_list" : [ "127.0.0.1:9876" ],
                                    "topic" : "test2",
                                    "producer_type": "sync",
                                    "key" : "key1",
                                    "batch_max_size": 1
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
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
        }
    }
--- error_log_like eval
qr/create new rocketmq producer instance, nameserver_list: \[\{"port":9876,"host":"127.0.0.127"}]/
qr/failed to send data to rocketmq topic: .*, nameserver_list: \{"127.0.0.127":9876}/



=== TEST 4: delete plugin metadata, tests would fail if run rocketmq-logger-log-format.t and plugin metadata is added
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/rocketmq-logger',
                ngx.HTTP_DELETE
            )
        }
    }
--- response_body



=== TEST 5: set route(id: 1,include_req_body = true,include_req_body_expr = array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : [ "127.0.0.1:9876" ],
                                "topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "include_req_body": true,
                                "include_req_body_expr": [
                                    [
                                      "arg_name",
                                      "==",
                                      "qwerty"
                                    ]
                                ],
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 6: hit route, expr eval success
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world

--- error_log eval
qr/send data to rocketmq: \{.*"body":"abcdef"/
--- wait: 2



=== TEST 7: hit route,expr eval fail
--- request
POST /hello?name=zcxv
abcdef
--- response_body
hello world
--- no_error_log eval
qr/send data to rocketmq: \{.*"body":"abcdef"/
--- wait: 2



=== TEST 8: check log schema(include_req_body)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                 topic = "test",
                 key = "key1",
                 nameserver_list = {
                    "127.0.0.1:3"
                 },
                 include_req_body = true,
                 include_req_body_expr = {
                     {"bar", "<>", "foo"}
                 }
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
failed to validate the 'include_req_body_expr' expression: invalid operator '<>'
done



=== TEST 9: check log schema(include_resp_body)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                 topic = "test",
                 key = "key1",
                 nameserver_list = {
                    "127.0.0.1:3"
                 },
                 include_resp_body = true,
                 include_resp_body_expr = {
                     {"bar", "<!>", "foo"}
                 }
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
failed to validate the 'include_resp_body_expr' expression: invalid operator '<!>'
done



=== TEST 10: set route(id: 1,include_resp_body = true,include_resp_body_expr = array)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : [ "127.0.0.1:9876" ],
                                "topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "include_resp_body": true,
                                "include_resp_body_expr": [
                                    [
                                      "arg_name",
                                      "==",
                                      "qwerty"
                                    ]
                                ],
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 11: hit route, expr eval success
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world

--- error_log eval
qr/send data to rocketmq: \{.*"body":"hello world\\n"/
--- wait: 2



=== TEST 12: set route include_resp_body = true - gzip
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : [ "127.0.0.1:9876" ],
                                "topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "include_resp_body": true,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:11451": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/gzip_hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 13: hit
--- http_config
server {
    listen 11451;
    gzip on;
    gzip_types *;
    gzip_min_length 1;
    location /gzip_hello {
        content_by_lua_block {
            ngx.req.read_body()
            local s = "gzip hello world"
            ngx.header['Content-Length'] = #s + 1
            ngx.say(s)
        }
    }
}
--- request
GET /gzip_hello
--- more_headers
Accept-Encoding: gzip
--- error_log eval
qr/send data to rocketmq: \{.*"body":"gzip hello world\\n"/
--- wait: 2



=== TEST 14: set route include_resp_body - brotli
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : [ "127.0.0.1:9876" ],
                                "topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "include_resp_body": true,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:11452": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/brotli_hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 15: hit route, expr eval success
--- http_config
server {
    listen 11452;
    location /brotli_hello {
        content_by_lua_block {
            ngx.req.read_body()
            local s = "brotli hello world"
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
--- request
GET /brotli_hello
--- more_headers
Accept-Encoding: br
--- error_log eval
qr/send data to rocketmq: \{.*"body":"brotli hello world\\n"/
--- wait: 2



=== TEST 16: hit route, expr eval fail
--- request
POST /hello?name=zcxv
abcdef
--- response_body
hello world
--- no_error_log eval
qr/send data to rocketmq: \{.*"body":"hello world\\n"/
--- wait: 2



=== TEST 17: multi level nested expr conditions
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                 topic = "test",
                 key = "key1",
                 nameserver_list = {
                    "127.0.0.1:3"
                 },
                 include_req_body = true,
                 include_req_body_expr = {
                    {"request_length", "<", 1024},
                    {"http_content_type", "in", {"application/xml", "application/json", "text/plain", "text/xml"}}
                 },
                 include_resp_body = true,
                 include_resp_body_expr = {
                    {"http_content_length", "<", 1024},
                    {"http_content_type", "in", {"application/xml", "application/json", "text/plain", "text/xml"}}
                 }
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 18: data encryption for secret_key
--- yaml_config
apisix:
    data_encryption:
        enable: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "rocketmq-logger": {
                                "nameserver_list" : [ "127.0.0.1:9876" ],
                                "topic" : "test2",
                                "access_key": "foo",
                                "secret_key": "bar"
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
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["rocketmq-logger"].secret_key)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["rocketmq-logger"].secret_key)
        }
    }
--- response_body
bar
77+NmbYqNfN+oLm0aX5akg==
