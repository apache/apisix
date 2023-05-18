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

run_tests;

__DATA__

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "desc": "test-desc",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]],
                [[{
                    "value": {
                        "remote_addr": "127.0.0.1",
                        "desc": "test-desc",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new route"
                    },
                    "key": "/apisix/stream_routes/1"
                }]]
                )

            ngx.status = code
            ngx.say(body)

            local res = assert(etcd.get('/stream_routes/1'))
            local create_time = res.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = res.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")

        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: get route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "value": {
                        "remote_addr": "127.0.0.1",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new route"
                    },
                    "key": "/apisix/stream_routes/1"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/stream_routes/1', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed



=== TEST 4: post route + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message, res = t('/apisix/admin/stream_routes',
                ngx.HTTP_POST,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]],
                [[{
                    "value": {
                        "remote_addr": "127.0.0.1",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "new route"
                    }
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.key, #"/apisix/stream_routes/" + 1)

            local ret = assert(etcd.get('/stream_routes/' .. id))
            local create_time = ret.body.node.value.create_time
            assert(create_time ~= nil, "create_time is nil")
            local update_time = ret.body.node.value.update_time
            assert(update_time ~= nil, "update_time is nil")
            id = ret.body.node.value.id
            assert(id ~= nil, "id is nil")

            code, message = t('/apisix/admin/stream_routes/' .. id, ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed



=== TEST 5: set route with plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 4
                        }
                    },
                    "upstream": {
                        "type": "chash",
                        "key": "mqtt_client_id",
                        "nodes": [
                            {
                                "host": "127.0.0.1",
                                "port": 1980,
                                "weight": 1
                            }
                        ]
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



=== TEST 6: set route with server_addr and server_port
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "server_addr": "127.0.0.1",
                    "server_port": 1982,
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 4
                        }
                    },
                    "upstream": {
                        "type": "chash",
                        "key": "mqtt_client_id",
                        "nodes": [
                            {
                                "host": "127.0.0.1",
                                "port": 1980,
                                "weight": 1
                            }
                        ]
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



=== TEST 7: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/stream_routes/1', ngx.HTTP_DELETE)
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 200 message: passed



=== TEST 8: string id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/a-b-c-ABC_0123',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
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



=== TEST 9: string id(delete)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/a-b-c-ABC_0123', ngx.HTTP_DELETE)
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



=== TEST 10: invalid string id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/*invalid',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
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
--- error_code: 400



=== TEST 11: not unwanted data, POST
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/stream_routes',
                 ngx.HTTP_POST,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            -- clean data
            local id = string.sub(res.key, #"/apisix/stream_routes/" + 1)
            local code, message = t('/apisix/admin/stream_routes/' .. id,
                 ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            assert(res.key ~= nil)
            res.key = nil
            assert(res.value.create_time ~= nil)
            res.value.create_time = nil
            assert(res.value.update_time ~= nil)
            res.value.update_time = nil
            assert(res.value.id ~= nil)
            res.value.id = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"value":{"remote_addr":"127.0.0.1","upstream":{"hash_on":"vars","nodes":{"127.0.0.1:8080":1},"pass_host":"pass","scheme":"http","type":"roundrobin"}}}
--- request
GET /t



=== TEST 12: not unwanted data, PUT
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            assert(res.value.create_time ~= nil)
            res.value.create_time = nil
            assert(res.value.update_time ~= nil)
            res.value.update_time = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"key":"/apisix/stream_routes/1","value":{"id":"1","remote_addr":"127.0.0.1","upstream":{"hash_on":"vars","nodes":{"127.0.0.1:8080":1},"pass_host":"pass","scheme":"http","type":"roundrobin"}}}
--- request
GET /t



=== TEST 13: not unwanted data, GET
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_GET
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            assert(res.createdIndex ~= nil)
            res.createdIndex = nil
            assert(res.modifiedIndex ~= nil)
            res.modifiedIndex = nil
            assert(res.value.create_time ~= nil)
            res.value.create_time = nil
            assert(res.value.update_time ~= nil)
            res.value.update_time = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"key":"/apisix/stream_routes/1","value":{"id":"1","remote_addr":"127.0.0.1","upstream":{"hash_on":"vars","nodes":{"127.0.0.1:8080":1},"pass_host":"pass","scheme":"http","type":"roundrobin"}}}
--- request
GET /t



=== TEST 14: not unwanted data, DELETE
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"deleted":"1","key":"/apisix/stream_routes/1"}
--- request
GET /t



=== TEST 15: set route with unknown plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "plugins": {
                        "mqttt-proxy": {
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"unknown plugin [mqttt-proxy]"}



=== TEST 16: validate protocol
--- extra_yaml_config
xrpc:
  protocols:
    - name: pingpong
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, case in ipairs({
                {input = {
                    name = "xxx",
                }},
                {input = {
                    name = "pingpong",
                }},
                {input = {
                    name = "pingpong",
                    conf = {
                        faults = "a",
                    }
                }},
            }) do
                local code, body = t('/apisix/admin/stream_routes/1',
                    ngx.HTTP_PUT,
                    {
                        protocol = case.input,
                        upstream = {
                            nodes = {
                                ["127.0.0.1:8080"] = 1
                            },
                            type = "roundrobin"
                        }
                    }
                )
                if code > 300 then
                    ngx.print(body)
                else
                    ngx.say(body)
                end
            end
        }
    }
--- request
GET /t
--- response_body
{"error_msg":"unknown protocol [xxx]"}
passed
{"error_msg":"property \"faults\" validation failed: wrong type: expected array, got string"}



=== TEST 17: set route with remote_addr and server_addr in IPV6
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "::1",
                    "server_addr": "::1",
                    "server_port": 1982,
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 4
                        }
                    },
                    "upstream": {
                        "type": "chash",
                        "key": "mqtt_client_id",
                        "nodes": [
                            {
                                "host": "127.0.0.1",
                                "port": 1980,
                                "weight": 1
                            }
                        ]
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
