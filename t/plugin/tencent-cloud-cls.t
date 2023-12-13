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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 10420;
        location /structuredlog {
            content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data()
                local headers = ngx.req.get_headers()
                ngx.log(ngx.WARN, "tencent-cloud-cls body: ", data)
                for k, v in pairs(headers) do
                    ngx.log(ngx.WARN, "tencent-cloud-cls headers: " .. k .. ":" .. v)
                end
                ngx.say("ok")
            }
        }
    }
    server {
        listen 10421;
        location /structuredlog {
            content_by_lua_block {
                ngx.exit(500)
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: schema check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tencent-cloud-cls")
            local ok, err = plugin.check_schema({
                cls_host = "ap-guangzhou.cls.tencentyun.com",
                cls_topic = "143b5d70-139b-4aec-b54e-bb97756916de",
                secret_id = "secret_id",
                secret_key = "secret_key",
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: cls config missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tencent-cloud-cls")
            local ok, err = plugin.check_schema({
                cls_host = "ap-guangzhou.cls.tencentyun.com",
                cls_topic = "143b5d70-139b-4aec-b54e-bb97756916de",
                secret_id = "secret_id",
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "secret_key" is required
done



=== TEST 3: add plugin for incorrect server
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tencent-cloud-cls": {
                                "cls_host": "127.0.0.1:10421",
                                "cls_topic": "143b5d70-139b-4aec-b54e-bb97756916de",
                                "secret_id": "secret_id",
                                "secret_key": "secret_key",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: incorrect server
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
Batch Processor[tencent-cloud-cls] failed to process entries [1/1]: got wrong status: 500
--- wait: 0.5



=== TEST 5: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tencent-cloud-cls": {
                                "cls_host": "127.0.0.1:10420",
                                "cls_topic": "143b5d70-139b-4aec-b54e-bb97756916de",
                                "secret_id": "secret_id",
                                "secret_key": "secret_key",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: access local server
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
Batch Processor[tencent-cloud-cls] successfully processed the entries
--- wait: 0.5



=== TEST 7: verify request
--- extra_init_by_lua
    local cls = require("apisix.plugins.tencent-cloud-cls.cls-sdk")
    cls.send_to_cls = function(self, logs)
        if (#logs ~= 1) then
            ngx.log(ngx.ERR, "unexpected logs length: ", #logs)
            return
        end
        return true
    end
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
Batch Processor[tencent-cloud-cls] successfully processed the entries
--- wait: 0.5



=== TEST 8: verify cls api request
--- extra_init_by_lua
    local cls = require("apisix.plugins.tencent-cloud-cls.cls-sdk")
    cls.send_cls_request = function(self, pb_obj)
        if (#pb_obj.logGroupList ~= 1) then
            ngx.log(ngx.ERR, "unexpected logGroupList length: ", #pb_obj.logGroupList)
            return false
        end
        local log_group = pb_obj.logGroupList[1]
        if #log_group.logs ~= 1 then
            ngx.log(ngx.ERR, "unexpected logs length: ", #log_group.logs)
            return false
        end
        local log = log_group.logs[1]
        if #log.contents == 0 then
            ngx.log(ngx.ERR, "unexpected contents length: ", #log.contents)
            return false
        end
        return true
    end
--- request
GET /opentracing
--- response_body
opentracing



=== TEST 9: plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tencent-cloud-cls")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/tencent-cloud-cls',
                 ngx.HTTP_PUT,
                 [[{
                        "log_format": {
                            "host": "$host",
                            "@timestamp": "$time_iso8601",
                            "client_ip": "$remote_addr"
                        }
                }]]
                )
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: log use log_format
--- extra_init_by_lua
    local cls = require("apisix.plugins.tencent-cloud-cls.cls-sdk")
    cls.send_cls_request = function(self, pb_obj)
        if (#pb_obj.logGroupList ~= 1) then
            ngx.log(ngx.ERR, "unexpected logGroupList length: ", #pb_obj.logGroupList)
            return false
        end
        local log_group = pb_obj.logGroupList[1]
        if #log_group.logs ~= 1 then
            ngx.log(ngx.ERR, "unexpected logs length: ", #log_group.logs)
            return false
        end
        local log = log_group.logs[1]
        if #log.contents == 0 then
            ngx.log(ngx.ERR, "unexpected contents length: ", #log.contents)
            return false
        end
        local has_host, has_timestamp, has_client_ip = false, false, false
        for i, tag in ipairs(log.contents) do
            if tag.key == "host" then
                has_host = true
            end
            if tag.key == "@timestamp" then
                has_timestamp = true
            end
            if tag.key == "client_ip" then
                has_client_ip = true
            end
        end
        if not(has_host and has_timestamp and has_client_ip) then
            return false
        end
        return true
    end
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 0.5



=== TEST 11: delete exist routes
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



=== TEST 12: data encryption for secret_key
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
                        "tencent-cloud-cls": {
                            "cls_host": "127.0.0.1:10421",
                            "cls_topic": "143b5d70-139b-4aec-b54e-bb97756916de",
                            "secret_id": "secret_id",
                            "secret_key": "secret_key",
                            "batch_max_size": 1,
                            "max_retry_count": 1,
                            "retry_delay": 2,
                            "buffer_duration": 2,
                            "inactive_timeout": 2
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

            ngx.say(res.value.plugins["tencent-cloud-cls"].secret_key)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["tencent-cloud-cls"].secret_key)
        }
    }
--- response_body
secret_key
oshn8tcqE8cJArmEILVNPQ==



=== TEST 13: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tencent-cloud-cls")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tencent-cloud-cls": {
                                "cls_host": "127.0.0.1:10421",
                                "cls_topic": "143b5d70-139b-4aec-b54e-bb97756916de",
                                "secret_id": "secret_id",
                                "secret_key": "secret_key",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "inactive_timeout": 1,
                                "log_format": {
                                    "host": "$host",
                                    "@timestamp": "$time_iso8601",
                                    "vip": "$remote_addr"
                                }
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
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: log use log_format
--- extra_init_by_lua
    local cls = require("apisix.plugins.tencent-cloud-cls.cls-sdk")
    cls.send_cls_request = function(self, pb_obj)
        if (#pb_obj.logGroupList ~= 1) then
            ngx.log(ngx.ERR, "unexpected logGroupList length: ", #pb_obj.logGroupList)
            return false
        end
        local log_group = pb_obj.logGroupList[1]
        if #log_group.logs ~= 1 then
            ngx.log(ngx.ERR, "unexpected logs length: ", #log_group.logs)
            return false
        end
        local log = log_group.logs[1]
        if #log.contents == 0 then
            ngx.log(ngx.ERR, "unexpected contents length: ", #log.contents)
            return false
        end
        local has_host, has_timestamp, has_vip = false, false, false
        for i, tag in ipairs(log.contents) do
            if tag.key == "host" then
                has_host = true
            end
            if tag.key == "@timestamp" then
                has_timestamp = true
            end
            if tag.key == "vip" then
                has_vip = true
            end
        end
        if not(has_host and has_timestamp and has_vip) then
            return false
        end
        return true
    end
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 0.5



=== TEST 15: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tencent-cloud-cls": {
                                "cls_host": "127.0.0.1:10420",
                                "cls_topic": "143b5d70-139b-4aec-b54e-bb97756916de",
                                "secret_id": "secret_id",
                                "secret_key": "secret_key",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
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

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: test resolvt e ip failed
--- extra_init_by_lua
    local socket = require("socket")
    socket.dns.toip = function(address)
        return nil, "address can't be resolved"
    end
--- request
GET /opentracing
--- response_body
opentracing
--- error_log eval
qr/resolve ip failed, hostname: .*, error: address can't be resolved/
--- wait: 0.5
