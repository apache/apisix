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
                    clickhouse = {
                        user = "default",
                        password = "a",
                        database = "default",
                        logtable = "t",
                        endpoint_addr = "http://127.0.0.1:1980/clickhouse_logger_server"
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



=== TEST 2: test unreachable server
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "clickhouse": {
                                "user": "default",
                                "password": "a",
                                "database": "default",
                                "logtable": "t",
                                "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server"
                    },
                    "inactive_timeout": 1
                }]]
                )
            ngx.sleep(2)
            core.log.warn("this is a warning message for test2.")
        }
    }
--- response_body
--- error_log
this is a warning message for test2
clickhouse body: INSERT INTO t FORMAT JSONEachRow
clickhouse headers: x-clickhouse-key:a
clickhouse headers: x-clickhouse-user:default
clickhouse headers: x-clickhouse-database:default
--- wait: 3



=== TEST 3: put plugin metadata and log an error level message
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "clickhouse": {
                        "user": "default",
                        "password": "a",
                        "database": "default",
                        "logtable": "t",
                        "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server"
                    },
                    "batch_max_size": 15,
                    "inactive_timeout": 1
                }]]
                )
            ngx.sleep(2)
            core.log.warn("this is a warning message for test3.")
        }
    }
--- response_body
--- error_log
this is a warning message for test3
clickhouse body: INSERT INTO t FORMAT JSONEachRow
clickhouse headers: x-clickhouse-key:a
clickhouse headers: x-clickhouse-user:default
clickhouse headers: x-clickhouse-database:default
--- wait: 5



=== TEST 4: log a warn level message
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.warn("this is a warning message for test4.")
        }
    }
--- response_body
--- error_log
this is a warning message for test4
clickhouse body: INSERT INTO t FORMAT JSONEachRow
clickhouse headers: x-clickhouse-key:a
clickhouse headers: x-clickhouse-user:default
clickhouse headers: x-clickhouse-database:default
--- wait: 5



=== TEST 5: log some messages
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.warn("this is a warning message for test5.")
        }
    }
--- response_body
--- error_log
this is a warning message for test5
clickhouse body: INSERT INTO t FORMAT JSONEachRow
clickhouse headers: x-clickhouse-key:a
clickhouse headers: x-clickhouse-user:default
clickhouse headers: x-clickhouse-database:default
--- wait: 5



=== TEST 6: log an info level message
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.info("this is an info message for test6.")
        }
    }
--- response_body
--- error_log
this is an info message for test6
--- wait: 5



=== TEST 7: delete metadata for the plugin, recover to the default
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



=== TEST 8: data encryption for clickhouse.password
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
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "clickhouse": {
                        "user": "default",
                        "password": "bar",
                        "database": "default",
                        "logtable": "t",
                        "endpoint_addr": "http://127.0.0.1:1980/clickhouse_logger_server"
                    },
                    "batch_max_size": 15,
                    "inactive_timeout": 1
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value["clickhouse"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/plugin_metadata/error-log-logger'))

            ngx.say(res.body.node.value["clickhouse"].password)
        }
    }
--- response_body
bar
77+NmbYqNfN+oLm0aX5akg==



=== TEST 9: verify use the decrypted password to connect to clickhouse
--- yaml_config
apisix:
    data_encryption:
        enable: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.warn("this is a warning message for test9")
        }
    }
--- response_body
--- error_log
this is a warning message for test9
clickhouse headers: x-clickhouse-key:bar
--- wait: 5
