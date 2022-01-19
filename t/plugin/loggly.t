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

    $block->set_value("stream_conf_enable", 1);

    if (!defined $block->extra_stream_config) {
        my $stream_config = <<_EOC_;
    server {
        listen 8126 udp;
        content_by_lua_block {
            -- mock statsd server is just accepts udp connection and log into error.log
            require("lib.mock_dogstatsd").go()
        }
    }
_EOC_
        $block->set_value("extra_stream_config", $stream_config);
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: sanity check metadata
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.loggly")
            local configs = {
                -- full configuration
                {
                    customer_token = "TEST-Token-Must-Be-Passed",
                    severity = "INFO",
                    tags = {"special-route", "highpriority-route"},
                    max_retry_count = 0,
                    retry_delay = 1,
                    buffer_duration = 60,
                    inactive_timeout = 2,
                    batch_max_size = 10,
                },
                -- minimize schema
                {
                    customer_token = "minimized-cofig",
                },
                -- property "customer_token" is required
                {
                    severity = "DEBUG",
                },
                -- unknown severity
                {
                    customer_token = "test",
                    severity = "UNKNOWN",
                },
                -- severity in lower case, should pass
                {
                    customer_token = "test",
                    severity = "crit",
                }
            }

            for i = 1, #configs do
                local ok, err = plugin.check_schema(configs[i])
                if not ok then
                    ngx.say(err)
                else
                    ngx.say("passed")
                end
            end
        }
    }
--- response_body
passed
passed
property "customer_token" is required
property "severity" validation failed: matches none of the enum values
passed



=== TEST 2: set route with loggly enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "loggly": {
                                "customer_token" : "test-token",
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "name": "loggly-enabled-route",
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



=== TEST 3: update loggly metadata with host port
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/loggly',
                 ngx.HTTP_PUT,
                 [[{
                        "host":"127.0.0.1",
                        "port": 8126
                }]],
                [[{
                    "node": {
                        "value": {
                            "host": "127.0.0.1",
                            "protocol": "syslog",
                            "timeout": 5000,
                            "port": 8126
                        },
                        "key": "/apisix/plugin_metadata/loggly"
                    },
                    "action": "set"
                }]])

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: testing udp packet with mock loggly udp suite
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- request 1
            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)

            -- request 2
            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- wait: 0.5
--- response_body
opentracing
opentracing
--- grep_error_log eval
qr/message received: .+?(?= \{)/
--- grep_error_log_out eval
qr/message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[test-token\@41058 ]
message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[test-token\@41058 ]/



=== TEST 5: checking loggly tags
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "loggly": {
                                "customer_token" : "token-1",
                                "batch_max_size": 1,
                                "tags": ["abc", "def"]
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

            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- wait: 0.5
--- response_body
passed
opentracing
--- grep_error_log eval
qr/message received: .+?(?= \{)/
--- grep_error_log_out eval
qr/message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[token-1\@41058 tag="abc" tag="def"]/



=== TEST 6: checking loggly log severity
log severity is calculated based on PRIVAL
8 + LOG_SEVERITY value
CRIT has value 2 so test should return PRIVAL <10>
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "loggly": {
                                "customer_token" : "token-1",
                                "batch_max_size": 1,
                                "severity": "CRIT"
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

            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- wait: 0.5
--- response_body
passed
opentracing
--- grep_error_log eval
qr/message received: .+?(?= \{)/
--- grep_error_log_out eval
qr/message received: <10>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[token-1\@41058 ]/
