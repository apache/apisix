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

=== TEST 1: should drop entries
--- extra_yaml_config
plugins:
  - kafka-logger
--- config
location /t {
    content_by_lua_block {
        local http = require "resty.http"
        local httpc = http.new()
        local data = {
            {
                input = {
                    plugins = {
                        ["kafka-logger"] = {
                            broker_list = {
                                ["127.0.0.1"] = 1234
                            },
                            kafka_topic = "test2",
                            producer_type = "sync",
                            timeout = 1,
                            batch_max_size = 1,
                            required_acks = 1,
                            meta_format = "origin",
                            max_retry_count = 10,
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        },
                        type = "roundrobin"
                    },
                    uri = "/hello",
                },
            },
        }

        local t = require("lib.test_admin").test

        -- Set plugin metadata
        local metadata = {
            log_format = {
                host = "$host",
                ["@timestamp"] = "$time_iso8601",
                client_ip = "$remote_addr"
            },
            max_pending_entries = 1
        }

        local code, body = t('/apisix/admin/plugin_metadata/kafka-logger', ngx.HTTP_PUT, metadata)
        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        -- Create route
        local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, data[1].input)
        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
        httpc:request_uri(uri, {
            method = "GET",
            keepalive_timeout = 1,
            keepalive_pool = 1,
        })
        httpc:request_uri(uri, {
            method = "GET",
            keepalive_timeout = 1,
            keepalive_pool = 1,
        })
        httpc:request_uri(uri, {
            method = "GET",
            keepalive_timeout = 1,
            keepalive_pool = 1,
        })
        ngx.sleep(2)
    }
}
--- error_log
max pending entries limit exceeded. discarding entry
--- timeout: 5



=== TEST 2: data encryption for brokers[].sasl_config.password
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
            local kafka_password = "super-secret-kafka-password"
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode({
                     plugins = {
                         ["kafka-logger"] = {
                             brokers = {{
                                 host = "127.0.0.1",
                                 port = 9092,
                                 sasl_config = {
                                     mechanism = "PLAIN",
                                     user = "admin",
                                     password = kafka_password,
                                 }
                             }},
                             kafka_topic = "test",
                             batch_max_size = 1,
                         }
                     },
                     upstream = {
                         nodes = {["127.0.0.1:1980"] = 1},
                         type = "roundrobin"
                     },
                     uri = "/hello"
                 })
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

            local plain = res.value.plugins["kafka-logger"].brokers[1].sasl_config.password
            ngx.say(plain == kafka_password)

            -- get plugin conf from etcd, password must be encrypted
            local etcd = require("apisix.core.etcd")
            local etcd_res = assert(etcd.get('/routes/1'))
            local stored = etcd_res.body.node.value
                              .plugins["kafka-logger"].brokers[1].sasl_config.password
            ngx.say(type(stored) == "string" and stored ~= "" and stored ~= kafka_password)
        }
    }
--- response_body
true
true
--- no_error_log
[alert]
