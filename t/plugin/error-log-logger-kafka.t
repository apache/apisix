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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
plugins:
    - error-log-logger
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: test schema checker
--- config
    location /t {
        content_by_lua_block {
        local core = require("apisix.core")
            local plugin = require("apisix.plugins.error-log-logger")
            local ok, err = plugin.check_schema(
                {
                    kafka = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = 9092
                            }
                        },
                        kafka_topic = "test2"
                    }
                },
                core.schema.TYPE_METADATA
            )
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: put plugin metadata and log an error level message - no auth kafka
--- extra_init_by_lua
    local core = require("apisix.core")
    local producer = require("resty.kafka.producer")
    local old_producer_new = producer.new
    producer.new = function(self, broker_list, producer_config, cluster_name)
        core.log.info("broker_config is: ", core.json.delay_encode(producer_config))
        return old_producer_new(self, broker_list, producer_config, cluster_name)
    end
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "kafka": {
                        "brokers": [{
                            "host": "127.0.0.1",
                            "port": 9092
                        }],
                        "kafka_topic": "test2",
                        "meta_refresh_interval": 1
                    },
                    "level": "ERROR",
                    "inactive_timeout": 1
                }]]
                )
            ngx.sleep(2)
            core.log.error("this is a error message for test2.")
        }
    }
--- error_log eval
[qr/this is a error message for test2/,
qr/send data to kafka: .*test2/,
qr/broker_config is: \{.*"refresh_interval":1000/,
]
--- wait: 3



=== TEST 3: log a error level message
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.error("this is a error message for test3.")
        }
    }
--- error_log eval
[qr/this is a error message for test3/,
qr/send data to kafka: .*test3/]
--- wait: 5



=== TEST 4: log an warning level message - will not send to kafka brokers
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.warn("this is an warning message for test4.")
        }
    }
--- error_log
this is an warning message for test4
--- no_error_log eval
qr/send data to kafka: .*test4/
--- wait: 5



=== TEST 5: put plugin metadata and log an error level message - auth kafka
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "kafka": {
                        "brokers": [{
                            "host": "127.0.0.1",
                            "port": 19094,
                            "sasl_config": {
                                "mechanism": "PLAIN",
                                "user": "admin",
                                "password": "admin-secret"
                            }
                        }],
                        "producer_type": "sync",
                        "kafka_topic": "test4"
                    },
                    "level": "ERROR",
                    "inactive_timeout": 1
                }]]
                )
            ngx.sleep(2)
            core.log.error("this is a error message for test5.")
        }
    }
--- error_log eval
[qr/this is a error message for test5/,
qr/send data to kafka: .*test5/]
--- wait: 3



=== TEST 6: delete metadata for the plugin, recover to the default
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: data encryption for kafka.brokers[].sasl_config.password (metadata)
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
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                 ngx.HTTP_PUT,
                 json.encode({
                     kafka = {
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
                     },
                     level = "ERROR",
                     inactive_timeout = 1,
                 })
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            -- get plugin metadata from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            local plain = res.value.kafka.brokers[1].sasl_config.password
            ngx.say(plain == kafka_password)

            -- get plugin metadata from etcd, password must be encrypted
            local etcd = require("apisix.core.etcd")
            local etcd_res = assert(etcd.get('/plugin_metadata/error-log-logger'))
            local stored = etcd_res.body.node.value.kafka.brokers[1].sasl_config.password
            ngx.say(type(stored) == "string" and stored ~= "" and stored ~= kafka_password)
        }
    }
--- response_body
true
true
--- no_error_log
[alert]



=== TEST 8: tls schema validation - valid tls config
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.error-log-logger")
            local ok, err = plugin.check_schema(
                {
                    kafka = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = 9093
                            }
                        },
                        kafka_topic = "test2",
                        tls = { verify = false }
                    }
                },
                core.schema.TYPE_METADATA
            )
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 9: tls schema validation - wrong type for verify
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.error-log-logger")
            local ok, err = plugin.check_schema(
                {
                    kafka = {
                        brokers = {
                            {
                                host = "127.0.0.1",
                                port = 9093
                            }
                        },
                        kafka_topic = "test2",
                        tls = { verify = "abc" }
                    }
                },
                core.schema.TYPE_METADATA
            )
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "kafka" validation failed: property "tls" validation failed: property "verify" validation failed: wrong type: expected boolean, got string
done



=== TEST 10: put metadata with kafka tls and log an error message - send via TLS
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "kafka": {
                        "brokers": [{
                            "host": "127.0.0.1",
                            "port": 9093
                        }],
                        "kafka_topic": "test2",
                        "meta_refresh_interval": 1,
                        "tls": {"verify": false}
                    },
                    "level": "ERROR",
                    "inactive_timeout": 1
                }]]
                )
            ngx.sleep(2)
            core.log.error("this is a error message for tls test.")
        }
    }
--- error_log eval
[qr/this is a error message for tls test/,
qr/sending a batch logs to kafka brokers: \[\{"host":"127.0.0.1","port":9093\}\]/,
qr/send data to kafka: .*this is a error message for tls test/]
--- no_error_log
failed to do SSL handshake
--- wait: 3
