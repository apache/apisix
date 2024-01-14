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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: data encryption work well with plugins that not the auth plugins
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "clickhouse-logger": {
                                "user": "default",
                                "password": "abc123",
                                "database": "default",
                                "logtable": "t",
                                "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server",
                                "batch_max_size":1,
                                "inactive_timeout":1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
            )

            ngx.sleep(0.5)

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

            ngx.say(res.value.plugins["clickhouse-logger"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["clickhouse-logger"].password)
        }
    }
--- response_body
abc123
7ipXoKyiZZUAgf3WWNPI5A==



=== TEST 2: verify
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
clickhouse body: INSERT INTO t FORMAT JSONEachRow
clickhouse headers: x-clickhouse-key:abc123
clickhouse headers: x-clickhouse-user:default
clickhouse headers: x-clickhouse-database:default
--- wait: 5



=== TEST 3: POST and get list
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes',
                 ngx.HTTP_POST,
                 [[{
                        "plugins": {
                            "clickhouse-logger": {
                                "user": "default",
                                "password": "abc123",
                                "database": "default",
                                "logtable": "t",
                                "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server",
                                "batch_max_size":1,
                                "inactive_timeout":1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
            )

            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/routes',
                ngx.HTTP_GET
            )
            res = json.decode(res)


            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.list[1].value.plugins["clickhouse-logger"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local id = res.list[1].value.id
            local key = "/routes/" .. id
            local res = assert(etcd.get(key))

            ngx.say(res.body.node.value.plugins["clickhouse-logger"].password)
        }
    }
--- response_body
abc123
7ipXoKyiZZUAgf3WWNPI5A==



=== TEST 4: PATCH
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "clickhouse-logger": {
                                "user": "default",
                                "password": "abc123",
                                "database": "default",
                                "logtable": "t",
                                "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server",
                                "batch_max_size":1,
                                "inactive_timeout":1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
            )

            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/routes/1/plugins',
                ngx.HTTP_PATCH,
                [[{
                        "clickhouse-logger": {
                            "user": "default",
                            "password": "def456",
                            "database": "default",
                            "logtable": "t",
                            "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server",
                            "batch_max_size":1,
                            "inactive_timeout":1
                        }
                 }]]
            )

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

            ngx.say(res.value.plugins["clickhouse-logger"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["clickhouse-logger"].password)
        }
    }
--- response_body
def456
3hlZu5mwUbqROm+cy0Vi9A==



=== TEST 5: data encryption work well with services
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "clickhouse-logger": {
                            "user": "default",
                            "password": "abc123",
                            "database": "default",
                            "logtable": "t",
                            "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server",
                            "batch_max_size":1,
                            "inactive_timeout":1
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_id": "1",
                    "uri": "/opentracing"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/services/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            ngx.say(res.value.plugins["clickhouse-logger"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/services/1'))
            ngx.say(res.body.node.value.plugins["clickhouse-logger"].password)
        }
    }
--- response_body
abc123
7ipXoKyiZZUAgf3WWNPI5A==



=== TEST 6: verify
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
clickhouse body: INSERT INTO t FORMAT JSONEachRow
clickhouse headers: x-clickhouse-key:abc123
clickhouse headers: x-clickhouse-user:default
clickhouse headers: x-clickhouse-database:default
--- wait: 5



=== TEST 7: data encryption work well with plugin_configs
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, err = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "clickhouse-logger": {
                            "user": "default",
                            "password": "abc123",
                            "database": "default",
                            "logtable": "t",
                            "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server",
                            "batch_max_size":1,
                            "inactive_timeout":1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugin_config_id": 1,
                    "uri": "/opentracing",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            ngx.say(res.value.plugins["clickhouse-logger"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/plugin_configs/1'))
            ngx.say(res.body.node.value.plugins["clickhouse-logger"].password)
        }
    }
--- response_body
abc123
7ipXoKyiZZUAgf3WWNPI5A==



=== TEST 8: verify
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
clickhouse body: INSERT INTO t FORMAT JSONEachRow
clickhouse headers: x-clickhouse-key:abc123
clickhouse headers: x-clickhouse-user:default
clickhouse headers: x-clickhouse-database:default
--- wait: 5



=== TEST 9: data encryption work well with global rule
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "test",
                    "plugins": {
                        "basic-auth": {
                            "username": "test",
                            "password": "test"
                        }
                    },
                    "desc": "test description"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {}
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            -- sleep for data sync
            ngx.sleep(0.5)
            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/consumers/test',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            ngx.say(res.value.plugins["basic-auth"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/test'))
            ngx.say(res.body.node.value.plugins["basic-auth"].password)

            -- hit the route with authorization
            local code, body = t('/hello',
                ngx.HTTP_PUT,
                nil,
                nil,
                {Authorization = "Basic dGVzdDp0ZXN0"}
            )
            if code ~= 200 then
                ngx.status = code
                return
            end

            -- delete global rule
            t('/apisix/admin/global_rules/1',
                ngx.HTTP_DELETE
            )
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
test
9QKrmTT3TkWGvjlIoe5XXw==
passed



=== TEST 10: data encryption work well with consumer groups
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/consumer_groups/company_a',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/consumers/foobar',
                ngx.HTTP_PUT,
                [[{
                    "username": "foobar",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-two"
                        }
                    },
                    "group_id": "company_a"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, key is decrypted
            local code, message, res = t('/apisix/admin/consumers/foobar',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["key-auth"].key)

            -- get plugin conf from etcd, key is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/foobar'))
            ngx.say(res.body.node.value.plugins["key-auth"].key)
        }
    }
--- response_body
auth-two
vU/ZHVJw7b0XscDJ1Fhtig==



=== TEST 11: verify data encryption
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local t = require("lib.test_admin").test
            local code, err = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "key-auth": {}
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.sleep(0.1)

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 3 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = {
                        ["apikey"] = "auth-two"
                    }
                })
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, res.status)
            end
            ngx.say(json.encode(ress))
        }
    }
--- response_body
[200,200,503]



=== TEST 12: verify whether print warning log when disable data_encryption
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                         "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- reponse_body
passed
--- no_error_log
failed to get schema for plugin
