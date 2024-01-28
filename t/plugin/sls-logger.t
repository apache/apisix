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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your-project", logstore = "your-logstore"
            , access_key_id = "your_access_key", access_key_secret = "your_access_secret"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: missing access_key_secret
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your-project", logstore = "your-logstore"
            , access_key_id = "your_access_key"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "access_key_secret" is required
done



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your_project", logstore = "your_logstore"
            , access_key_id = "your_access_key", access_key_secret = "your_access_secret", timeout = "10"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "timeout" validation failed: wrong type: expected integer, got string
done



=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "sls-logger": {
                                "host": "100.100.99.135",
                                "port": 10009,
                                "project": "your_project",
                                "logstore": "your_logstore",
                                "access_key_id": "your_access_key_id",
                                "access_key_secret": "your_access_key_secret",
                                "timeout": 30000
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
        }
    }
--- response_body
passed



=== TEST 5: access
--- request
GET /hello
--- response_body
hello world
--- wait: 1



=== TEST 6: test combine log
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local entities = {}
            table.insert(entities, {data = "1"})
            table.insert(entities, {data = "2"})
            table.insert(entities, {data = "3"})
            local data =  plugin.combine_syslog(entities)
            ngx.say(data)
        }
    }
--- response_body
123



=== TEST 7: sls log get milliseconds
--- config
    location /t {
        content_by_lua_block {
            local function get_syslog_timestamp_millisecond(log_entry)
                local first_idx = string.find(log_entry, " ") + 1
                local last_idx2 = string.find(log_entry, " ", first_idx)
                local rfc3339_date = string.sub(log_entry, first_idx, last_idx2)
                local rfc3339_len = #rfc3339_date
                local rfc3339_millisecond = string.sub(rfc3339_date, rfc3339_len - 4, rfc3339_len - 2)
                return tonumber(rfc3339_millisecond)
            end

            math.randomseed(os.time())
            local rfc5424 = require("apisix.utils.rfc5424")
            local m = 0
            -- because the millisecond value obtained by `ngx.now` may be `0`
            -- it is executed multiple times to ensure the accuracy of the test
            for i = 1, 5 do
                ngx.sleep(string.format("%0.3f", math.random()))
                local structured_data = {
                    {name = "project", value = "apisix.apache.org"},
                    {name = "logstore", value = "apisix.apache.org"},
                    {name = "access-key-id", value = "apisix.sls.logger"},
                    {name = "access-key-secret", value = "BD274822-96AA-4DA6-90EC-15940FB24444"}
                }
                local log_entry = rfc5424.encode("SYSLOG", "INFO", "localhost", "apisix",
                                                 123456, "hello world", structured_data)
                m = get_syslog_timestamp_millisecond(log_entry) + m
            end

            if m > 0 then
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
--- timeout: 5



=== TEST 8: add log format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/sls-logger',
                 ngx.HTTP_PUT,
                 [[{
                    "log_format": {
                        "host": "$host",
                        "client_ip": "$remote_addr"
                    }
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



=== TEST 9: access
--- extra_init_by_lua
    local json = require("toolkit.json")
    local rfc5424 = require("apisix.utils.rfc5424")
    local old_f = rfc5424.encode
    rfc5424.encode = function(facility, severity, hostname, appname, pid, msg, structured_data)
        local r = json.decode(msg)
        assert(r.client_ip == "127.0.0.1", r.client_ip)
        assert(r.host == "localhost", r.host)
        return old_f(facility, severity, hostname, appname, pid, msg, structured_data)
    end
--- request
GET /hello
--- response_body
hello world



=== TEST 10: delete exist routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- delete exist consumers
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: data encryption for access_key_secret
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
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
                            "sls-logger": {
                                "host": "100.100.99.135",
                                "port": 10009,
                                "project": "your_project",
                                "logstore": "your_logstore",
                                "access_key_id": "your_access_key_id",
                                "access_key_secret": "your_access_key_secret",
                                "timeout": 30000
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

            ngx.say(res.value.plugins["sls-logger"].access_key_secret)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["sls-logger"].access_key_secret)
        }
    }
--- response_body
your_access_key_secret
1T6nR0fz4yhz/zTuRTvt7Xu3c9ASelDXG2//e/A5OiA=



=== TEST 12: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "sls-logger": {
                                "host": "100.100.99.135",
                                "port": 10009,
                                "project": "your_project",
                                "logstore": "your_logstore",
                                "access_key_id": "your_access_key_id",
                                "access_key_secret": "your_access_key_secret",
                                "log_format": {
                                    "vip": "$remote_addr"
                                },
                                "timeout": 30000
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
        }
    }
--- response_body
passed



=== TEST 13: access
--- extra_init_by_lua
    local json = require("toolkit.json")
    local rfc5424 = require("apisix.utils.rfc5424")
    local old_f = rfc5424.encode
    rfc5424.encode = function(facility, severity, hostname, appname, pid, msg, structured_data)
        local r = json.decode(msg)
        assert(r.vip == "127.0.0.1", r.vip)
        return old_f(facility, severity, hostname, appname, pid, msg, structured_data)
    end
--- request
GET /hello
--- response_body
hello world



=== TEST 14: add plugin with 'include_req_body' setting, collect request log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/sls-logger', ngx.HTTP_DELETE)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "sls-logger": {
                                "host": "127.0.0.1",
                                "port": 10009,
                                "project": "your_project",
                                "logstore": "your_logstore",
                                "access_key_id": "your_access_key_id",
                                "access_key_secret": "your_access_key_secret",
                                "timeout": 30000,
                                "include_req_body": true
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

            local code, _, body = t("/hello", "POST", "{\"sample_payload\":\"hello\"}")
        }
    }
--- error_log
\"body\":\"{\\\"sample_payload\\\":\\\"hello\\\"



=== TEST 15: add plugin with 'include_resp_body' setting, collect response log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/sls-logger', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "sls-logger": {
                                "host": "127.0.0.1",
                                "port": 10009,
                                "project": "your_project",
                                "logstore": "your_logstore",
                                "access_key_id": "your_access_key_id",
                                "access_key_secret": "your_access_key_secret",
                                "timeout": 30000,
                                "include_req_body": true,
                                "include_resp_body": true
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

            local code, _, body = t("/hello", "POST", "{\"sample_payload\":\"hello\"}")
        }
    }
--- error_log
\"body\":\"hello world\\n\"
