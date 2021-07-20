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
run_tests;

__DATA__

=== TEST 1: test schema checker
--- config
    location /t {
        content_by_lua_block {
	    local core = require("apisix.core")
            local plugin = require("apisix.plugins.error-log-skywalking-logger")
            local ok, err = plugin.check_schema({endpoint = "http://127.0.0.1"}, core.schema.TYPE_METADATA)
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



=== TEST 2: test schema checker, missing required field
--- config
    location /t {
        content_by_lua_block {
	    local core = require("apisix.core")
            local plugin = require("apisix.plugins.error-log-skywalking-logger")
            local ok, err = plugin.check_schema({uri = "http://127.0.0.1"}, core.schema.TYPE_METADATA)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "endpoint" is required
done
--- no_error_log
[error]



=== TEST 3: not enable the plugin
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
--- no_error_log
error-log-skywalking-logger
--- wait: 2



=== TEST 4: enable the plugin, but not init the metadata
--- yaml_config
plugins:
  - error-log-skywalking-logger
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
qr/please set the correct plugin_metadata for error-log-skywalking-logger/
--- wait: 2



=== TEST 5: set a wrong metadata
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-skywalking-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-skywalking-logger',
                ngx.HTTP_PUT,
                [[{
                    "port": 1999,
                    "inactive_timeout": 1
                }]]
                )

            -- ensure the request is rejected even this plugin doesn't
            -- have check_schema method
            ngx.status = code
            core.log.warn("this is a warning message for test.")
        }
    }
--- request
GET /tg
--- error_code: 400
--- response_body
--- error_log eval
qr/please set the correct plugin_metadata for error-log-skywalking-logger/
--- wait: 2



=== TEST 6: test unreachable server
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-skywalking-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-skywalking-logger',
                ngx.HTTP_PUT,
                [[{
		            "endpoint": "http://127.0.0.1:1988/log",
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
qr/.*\[lua\] batch-processor.lua:63: Batch Processor\[error-log-skywalking-logger\] failed to process entries: failed to connect to host\[127.0.0.1\] port\[1988\] connection refused, context: ngx.timer/
--- wait: 3



=== TEST 7: put plugin metadata
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-skywalking-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-skywalking-logger',
                ngx.HTTP_PUT,
                [[{
                    "endpoint": "http://127.0.0.1:1982/log",
                    "inactive_timeout": 1
                }]]
                )
        }
    }
--- request
GET /tg
--- response_body
--- no_error_log
[error]



=== TEST 8: log an error level message
--- yaml_config
plugins:
  - error-log-skywalking-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.sleep(2)
            core.log.error("this is an error message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- error_log eval
qr/.*\[\{\"body\":\{\"text\":\{\"text\":\".*\"\}\},\"endpoint\":\"\",\"service\":\"APISIX\",\"serviceInstance\":\"APISIX Service Instance\".*/
--- wait: 5



=== TEST 9: delete metadata for the plugin, recover to the default
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-skywalking-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-skywalking-logger',
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



=== TEST 10: want to reload the plugin by route
--- yaml_config
apisix:
    enable_admin: true
    admin_key: null
plugins:
  - error-log-skywalking-logger
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "error-log-skywalking-logger": {
                            "endpoint": "127.0.0.1:9092",
                            "inactive_timeout": 1
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello1"
                }]]
                )
            -- reload
            code, body = t('/apisix/admin/plugins/reload',
                                    ngx.HTTP_PUT)
            core.log.warn("this is a warning message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- error_log eval
qr/please set the correct plugin_metadata for error-log-skywalking-logger/
--- wait: 2



=== TEST 11: delete the route
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
            local code, body = t('/apisix/admin/routes/1',
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
