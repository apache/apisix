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
worker_connections(128);
run_tests;

__DATA__

=== TEST 1: test schema checker
--- config
    location /t {
        content_by_lua_block {
        local core = require("apisix.core")
            local plugin = require("apisix.plugins.error-log-logger")
            local ok, err = plugin.check_schema(
                {
                    skywalking = {
                        endpoint_addr = "http://127.0.0.1"
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
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: test unreachable server
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "skywalking": {
                        "endpoint_addr": "http://127.0.0.1:1988/log"
                    },
                    "inactive_timeout": 1
                }]]
                )
            ngx.sleep(2)
            core.log.warn("this is a warning message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- error_log eval
qr/.*\[lua\] batch-processor.lua:63: Batch Processor\[error-log-logger\] failed to process entries: error while sending data to skywalking\[http:\/\/127.0.0.1:1988\/log\] connection refused, context: ngx.timer/
--- wait: 3



=== TEST 3: put plugin metadata and log an error level message
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "skywalking": {
                        "endpoint_addr": "http://127.0.0.1:1982/log",
                        "service_instance_name": "instance"
                    },
                    "batch_max_size": 15,
                    "inactive_timeout": 1
                }]]
                )
            ngx.sleep(2)
            core.log.error("this is an error message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- error_log eval
qr/.*\[\{\"body\":\{\"text\":\{\"text\":\".*this is an error message for test.*\"\}\},\"endpoint\":\"\",\"service\":\"APISIX\",\"serviceInstance\":\"instance\".*/
--- wait: 5



=== TEST 4: log a warn level message
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.warn("this is a warning message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- error_log eval
qr/.*\[\{\"body\":\{\"text\":\{\"text\":\".*this is a warning message for test.*\"\}\},\"endpoint\":\"\",\"service\":\"APISIX\",\"serviceInstance\":\"instance\".*/
--- wait: 5



=== TEST 5: log some messages
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.error("this is an error message for test.")
            core.log.warn("this is a warning message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- error_log eval
qr/.*\[\{\"body\":\{\"text\":\{\"text\":\".*this is an error message for test.*\"\}\},\"endpoint\":\"\",\"service\":\"APISIX\",\"serviceInstance\":\"instance\".*\},\{\"body\":\{\"text\":\{\"text\":\".*this is a warning message for test.*\"\}\}.*/
--- wait: 5



=== TEST 6: log an info level message
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.info("this is an info message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- no_error_log eval
qr/.*\[\{\"body\":\{\"text\":\{\"text\":\".*this is an info message for test.*\"\}\},\"endpoint\":\"\",\"service\":\"APISIX\",\"serviceInstance\":\"instance\".*/
--- wait: 5



=== TEST 7: delete metadata for the plugin, recover to the default
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-logger
--- config
    location /tg {
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
--- request
GET /tg
--- response_body
passed
--- no_error_log
[error]
