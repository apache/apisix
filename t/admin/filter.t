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
worker_connections(1024);
no_root_location();
no_shuffle();

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
    proxy_mode: http&stream
_EOC_
    $block->set_value("yaml_config", $user_yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: bad page_size(page_size must be between 10 and 500)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            ngx.sleep(0.5)

            local code, body = t('/apisix/admin/routes/?page=1&page_size=2',
                ngx.HTTP_GET
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body
page_size must be between 10 and 500



=== TEST 2: ignore bad page and would use default value 1
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?page=-1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 10)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: sort by createdIndex
# the smaller the createdIndex, the higher the ranking
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?page=1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)

            for i = 1, #res.list - 1 do
                assert(res.list[i].createdIndex < res.list[i + 1].createdIndex)
            end
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: routes pagination
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?page=1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 10)

            code, body, res = t('/apisix/admin/routes/?page=2&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 1)

            code, body, res = t('/apisix/admin/routes/?page=3&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 0)

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: services pagination
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/services/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/services/?page=1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 10)

            code, body, res = t('/apisix/admin/services/?page=2&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 1)

            code, body, res = t('/apisix/admin/services/?page=3&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 0)

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: only search name or labels
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/services/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "name": "]] .. i .. [[",
                        "labels": {"]] .. i .. '":"' .. i .. [["}
                    }]]
                )
            end

            ngx.sleep(0.5)

            local matched = {1, 10, 11}

            local code, body, res = t('/apisix/admin/services/?name=1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            -- match the name are 1, 10, 11
            assert(#res.list == 3)

            for _, node in ipairs(res.list) do
                assert(core.table.array_find(matched, tonumber(node.value.name)))
            end

            code, body, res = t('/apisix/admin/services/?label=1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            -- match the label are 1, 10, 11
            assert(#res.list == 1)
            assert(res.list[1].value.id == "1")

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: services filter
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/services/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "name": "]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/services/?name=1',
                ngx.HTTP_GET
            )
            res = json.decode(res)

            -- match the name and label are 1, 10, 11
            assert(#res.list == 3)

            local matched = {1, 10, 11}
            for _, node in ipairs(res.list) do
                assert(core.table.array_find(matched, tonumber(node.value.name)))
            end

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: routes filter
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "name": "]] .. i .. [[",
                        "uri": "]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/services/?name=1',
                ngx.HTTP_GET
            )
            res = json.decode(res)

            -- match the name and label are 1, 10, 11
            assert(#res.list == 3)

            local matched = {1, 10, 11}
            for _, node in ipairs(res.list) do
                assert(core.table.array_find(matched, tonumber(node.value.name)))
            end

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: filter with pagination
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local code, body, res = t('/apisix/admin/services/?name=1&page=1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)

            -- match the name and label are 1, 10, 11
            -- we do filtering first now, so it will first filter to 1, 10, 11, and then paginate
            -- res will contain 1, 10, 11 instead of just 1, 10.
            assert(#res.list == 3)

            local matched = {1, 10, 11}
            for _, node in ipairs(res.list) do
                assert(core.table.array_find(matched, tonumber(node.value.name)))
            end

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: routes filter with uri
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "name": "]] .. i .. [[",
                        "uri": "]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?uri=1',
                ngx.HTTP_GET
            )
            res = json.decode(res)

            -- match the name and label are 1, 10, 11
            assert(#res.list == 3)

            local matched = {1, 10, 11}
            for _, node in ipairs(res.list) do
                assert(core.table.array_find(matched, tonumber(node.value.name)))
            end

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: match labels
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
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
                    "uri": "/hello",
                    "labels": {
                        "env": "production"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello2",
                    "labels": {
                        "env2": "production"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)

            -- only match labels' keys
            local code, body, res = t('/apisix/admin/routes/?label=env',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 1)
            assert(res.list[1].value.id == "1")

            -- don't match labels' values
            code, body, res = t('/apisix/admin/routes/?label=production',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 0)

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: match uris
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
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
                    "uris": ["/hello", "/world"]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/foo", "/bar"]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?uri=world',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 1)
            assert(res.list[1].value.id == "1")

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: match uris & labels
# uris are same in different routes, filter by labels
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
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
                    "uris": ["/hello", "/world"],
                    "labels": {
                        "env": "production"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/hello", "/world"],
                    "labels": {
                        "build": "16"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)

            -- only match route 1
            local code, body, res = t('/apisix/admin/routes/?uri=world&label=env',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 1)
            assert(res.list[1].value.id == "1")

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: match uri & labels
# uri is same in different routes, filter by labels
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local core = require("apisix.core")
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
                    "uri": "/hello",
                    "labels": {
                        "env": "production"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello",
                    "labels": {
                        "env2": "production"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?uri=hello&label=env',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 1)
            assert(res.list[1].value.id == "1")

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: filtered data total
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, body, res = t('/apisix/admin/routes', ngx.HTTP_GET)
            res = json.decode(res)
            assert(res.total == 11)
            assert(#res.list == 11)

            local code, body, res = t('/apisix/admin/routes/?label=', ngx.HTTP_GET)
            res = json.decode(res)
            assert(res.total == 0)
            assert(#res.list == 0)

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: pagination data total
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, body, res = t('/apisix/admin/routes?page=1&page_size=10', ngx.HTTP_GET)
            res = json.decode(res)
            assert(res.total == 11)
            assert(#res.list == 10)

            local code, body, res = t('/apisix/admin/routes?page=10&page_size=10', ngx.HTTP_GET)
            res = json.decode(res)
            assert(res.total == 11)
            assert(#res.list == 0)

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST: 17: filter by route service_id/upstream_id
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            -- create a service
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            -- create a upstream
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin"
                }]]
            )

            for i = 1, 11 do
                local route = { uri = "/hello" .. i }
                if i % 2 == 0 then
                    route.service_id = "1"
                else
                    route.upstream_id = "1"
                end
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    json.encode(route)
                )
            end

            ngx.sleep(0.5)

            -- check service_id
            local code, body, res = t('/apisix/admin/routes?filter='
                                        .. ngx.encode_args({ service_id = "1" }),
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 5, "expected 5 routes with service_id 1, got " .. #res.list)

            for i = 1, #res.list do
                assert(tonumber(res.list[i].value.id) % 2 == 0,
                       "expected route id to be even, got " .. res.list[i].value.id)
                assert(res.list[i].value.service_id == "1",
                       "expected service_id 1, got " .. tostring(res.list[i].value.service_id))
            end

            -- check upstream_id
            local code, body, res = t('/apisix/admin/routes?filter='
                                        .. ngx.encode_args({ upstream_id = "1" }),
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 6, "expected 6 routes with upstream_id 1, got " .. #res.list)

            for i = 1, #res.list do
                assert(tonumber(res.list[i].value.id) % 2 == 1,
                       "expected route id to be odd, got " .. res.list[i].value.id)
                assert(res.list[i].value.upstream_id == "1",
                       "expected upstream_id 1, got " .. tostring(res.list[i].value.upstream_id))
            end
        }
    }
--- error_code: 200



=== TEST: 18: filter by stream route service_id/upstream_id
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            -- create a service
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            -- create a upstream
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin"
                }]]
            )

            for i = 1, 11 do
                local route = { server_port = 5432 }
                if i % 2 == 0 then
                    route.service_id = "1"
                else
                    route.upstream_id = "1"
                end
                local code, body = t('/apisix/admin/stream_routes/' .. i,
                    ngx.HTTP_PUT,
                    json.encode(route),
                )
            end

            ngx.sleep(0.5)

            -- check service_id
            local code, body, res = t('/apisix/admin/stream_routes?filter='
                                        .. ngx.encode_args({ service_id = "1" }),
                ngx.HTTP_GET
            )
            res = json.decode(res)

            assert(#res.list == 5, "expected 5 stream routes with service_id 1, got " .. #res.list)
            
            for i = 1, #res.list do
                assert(tonumber(res.list[i].value.id) % 2 == 0,
                       "expected stream route id to be even, got " .. res.list[i].value.id)
                assert(res.list[i].value.service_id == "1",
                       "expected service_id 1, got " .. tostring(res.list[i].value.service_id))
            end

            -- check upstream_id
            local code, body, res = t('/apisix/admin/stream_routes?filter='
                                        .. ngx.encode_args({ upstream_id = "1" }),
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 6, "expected 6 stream routes with upstream_id 1, got " .. #res.list)
            
            for i = 1, #res.list do
                assert(tonumber(res.list[i].value.id) % 2 == 1,
                       "expected stream route id to be odd, got " .. res.list[i].value.id)
                assert(res.list[i].value.upstream_id == "1",
                       "expected upstream_id 1, got " .. tostring(res.list[i].value.upstream_id))
            end
        }
    }
--- error_code: 200
