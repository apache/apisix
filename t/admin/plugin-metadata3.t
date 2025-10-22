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

    # setup default conf.yaml
    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
        - abcdef1234567890
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: First get not exist plugin metadata when plugin.enable_data_encryption is nil
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugin")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_GET
            )

            local_conf, err = core.config.local_conf(true)
            local enable_data_encryption =
            core.table.try_read_attr(local_conf, "apisix", "data_encryption",
                    "enable_encrypt_fields") and (core.config.type == "etcd")

            ngx.status = code
            ngx.say(enable_data_encryption)
            ngx.say(plugin.enable_data_encryption) -- When no plugin configuration in the init phase. enable_data_encryption is not initialized
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body_like
true
nil
\{"message":"Key not found"\}



=== TEST 2: add example-plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                ngx.HTTP_PUT,
                [[{
                    "skey": "val",
                    "ikey": 1
                }]],
                [[{
                    "value": {
                        "skey": "val",
                        "ikey": 1
                    },
                    "key": "/apisix/plugin_metadata/example-plugin"
                }]]
            )

            ngx.status = 200
            ngx.say(plugin.enable_data_encryption)  -- Trigger plugin.enable_data_encryption to synchronize the conf configuration
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
true
passed



=== TEST 3: Second get not exist plugin metadata when plugin.enable_data_encryption is true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/http-logger',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body_like
{"message":"Key not found"}



=== TEST 4: update example-plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                ngx.HTTP_PUT,
                [[{
                    "skey": "val2",
                    "ikey": 2
                }]],
                [[{
                    "value": {
                        "skey": "val2",
                        "ikey": 2
                    },
                    "key": "/apisix/plugin_metadata/example-plugin"
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



=== TEST 5: get plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                 ngx.HTTP_GET
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: delete plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                ngx.HTTP_DELETE
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 7: get deleted example-plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/example-plugin',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.say(plugin.enable_data_encryption) -- When no plugin configuration in the init phase. enable_data_encryption is not initialized
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body_like
nil
\{"message":"Key not found"\}
