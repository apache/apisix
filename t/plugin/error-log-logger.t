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

    my $stream_single_server = <<_EOC_;
    # fake server, only for test
    server {
        listen 1999;

        content_by_lua_block {
            local exiting = ngx.worker.exiting
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.WARN, "socket error:", err)
                return
            end

            sock:settimeout(30 * 1000)
            while(not exiting())
            do
                local data, err =  sock:receive()
                if (data) then
                    ngx.log(ngx.INFO, "[Server] receive data:", data)
                else
                    if err ~= "timeout" then
                        ngx.log(ngx.WARN, "socket error:", err)
                        return
                    end
                end
            end

        }
    }
_EOC_

    $block->set_value("stream_config", $stream_single_server);

    my $stream_default_server = <<_EOC_;
        content_by_lua_block {
            ngx.log(ngx.INFO, "a stream server")
        }
_EOC_

    $block->set_value("stream_server_config", $stream_default_server);

    if (!defined $block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
plugins:
    - error-log-logger
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

});

run_tests;

__DATA__

=== TEST 1: not enable the plugin
--- extra_yaml_config
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
error-log-logger
--- wait: 2



=== TEST 2: enable the plugin, but not init the metadata
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
qr/please set the correct plugin_metadata for error-log-logger/
--- wait: 2



=== TEST 3: set a wrong metadata
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "tcp": {
                        "port": 1999
                    },
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
qr/please set the correct plugin_metadata for error-log-logger/
--- wait: 2



=== TEST 4: test unreachable server
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "tcp": {
                        "host": "127.0.0.1",
                        "port": 2999
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
--- no_error_log eval
qr/\[Server\] receive data:.*this is a warning message for test./
--- wait: 3



=== TEST 5: log a warn level message
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "tcp": {
                        "host": "127.0.0.1",
                        "port": 1999
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
qr/\[Server\] receive data:.*this is a warning message for test./
--- wait: 5



=== TEST 6: log an error level message
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
qr/\[Server\] receive data:.*this is an error message for test./
--- wait: 5



=== TEST 7: log an info level message
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.sleep(2)
            core.log.info("this is an info message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- no_error_log eval
qr/\[Server\] receive data:.*this is an info message for test./
--- wait: 5



=== TEST 8: delete metadata for the plugin, recover to the default
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



=== TEST 9: want to reload the plugin by route
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "error-log-logger": {
                            "tcp": {
                                "host": "127.0.0.1",
                                "port": 1999
                            },
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
qr/please set the correct plugin_metadata for error-log-logger/
--- wait: 2



=== TEST 10: avoid sending stale error log
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            core.log.warn("this is a warning message for test.")
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "tcp": {
                        "host": "127.0.0.1",
                        "port": 1999
                    },
                    "level": "ERROR",
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
--- no_error_log eval
qr/\[Server\] receive data:.*this is a warning message for test./
--- error_log eval
qr/\[Server\] receive data:.*this is an error message for test./
--- wait: 5



=== TEST 11: delete the route
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



=== TEST 12: log a warn level message (schema compatibility testing)
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/error-log-logger',
                ngx.HTTP_PUT,
                [[{
                    "tcp": {
                        "host": "127.0.0.1",
                        "port": 1999
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
qr/\[Server\] receive data:.*this is a warning message for test./
--- wait: 5



=== TEST 13: log an error level message (schema compatibility testing)
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
qr/\[Server\] receive data:.*this is an error message for test./
--- wait: 5



=== TEST 14: log an info level message (schema compatibility testing)
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.sleep(2)
            core.log.info("this is an info message for test.")
        }
    }
--- request
GET /tg
--- response_body
--- no_error_log eval
qr/\[Server\] receive data:.*this is an info message for test./
--- wait: 5



=== TEST 15: delete metadata for the plugin, recover to the default (schema compatibility testing)
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
