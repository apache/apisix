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
            -- mock udp server is just accepts udp connection and log into error.log
            require("lib.mock_layer4").loggly()
        }
    }
_EOC_
        $block->set_value("extra_stream_config", $stream_config);
    }

    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 10420;

        location /loggly/bulk/tok/tag/bulk {
            content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data()
                local headers = ngx.req.get_headers()
                ngx.log(ngx.ERR, "loggly body: ", data)
                ngx.log(ngx.ERR, "loggly tags: " .. require("toolkit.json").encode(headers["X-LOGGLY-TAG"]))
                ngx.say("ok")
            }
        }

        location /loggly/503 {
            content_by_lua_block {
                ngx.status = 503
                ngx.say("service temporarily unavailable")
                ngx.exit(ngx.OK)
            }
        }

        location /loggly/410 {
            content_by_lua_block {
                ngx.status = 410
                ngx.say("expired link")
                ngx.exit(ngx.OK)
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

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
                }]]
                )

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
qr/message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[test-token\@41058 tag="apisix"]
message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[test-token\@41058 tag="apisix"]/



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
qr/message received: <10>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[token-1\@41058 tag="apisix"]/



=== TEST 7: collect response full log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- response_body
opentracing
--- grep_error_log eval
qr/message received: [ -~]+/
--- grep_error_log_out eval
qr/message received: <10>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[token-1\@41058 tag="apisix"] \{"apisix_latency":[\d.]*,"client_ip":"127\.0\.0\.1","latency":[\d.]*,"request":\{"headers":\{"content-type":"application\/x-www-form-urlencoded","host":"127\.0\.0\.1:1984","user-agent":"lua-resty-http\/[\d.]* \(Lua\) ngx_lua\/[\d]*"\},"method":"GET","querystring":\{\},"size":[\d]+,"uri":"\/opentracing","url":"http:\/\/127\.0\.0\.1:1984\/opentracing"\},"response":\{"headers":\{"connection":"close","content-type":"text\/plain","server":"APISIX\/[\d.]+","transfer-encoding":"chunked"\},"size":[\d]*,"status":200\},"route_id":"1","server":\{"hostname":"[ -~]*","version":"[\d.]+"\},"service_id":"","start_time":[\d]*,"upstream":"127\.0\.0\.1:1982","upstream_latency":[\d]*\}/



=== TEST 8: collect response log with include_resp_body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "loggly": {
                                "customer_token" : "tok",
                                "batch_max_size": 1,
                                "include_resp_body": true
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
--- response_body
passed
opentracing
--- grep_error_log eval
qr/message received: [ -~]+/
--- grep_error_log_out eval
qr/message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[tok\@41058 tag="apisix"] \{"apisix_latency":[\d.]*,"client_ip":"127\.0\.0\.1","latency":[\d.]*,"request":\{"headers":\{"content-type":"application\/x-www-form-urlencoded","host":"127\.0\.0\.1:1984","user-agent":"lua-resty-http\/[\d.]* \(Lua\) ngx_lua\/[\d]*"\},"method":"GET","querystring":\{\},"size":[\d]+,"uri":"\/opentracing","url":"http:\/\/127\.0\.0\.1:1984\/opentracing"\},"response":\{"body":"opentracing\\n","headers":\{"connection":"close","content-type":"text\/plain","server":"APISIX\/[\d.]+","transfer-encoding":"chunked"\},"size":[\d]*,"status":200\},"route_id":"1","server":\{"hostname":"[ -~]*","version":"[\d.]+"\},"service_id":"","start_time":[\d]*,"upstream":"127\.0\.0\.1:1982","upstream_latency":[\d]*\}/



=== TEST 9: collect log with include_resp_body_expr
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "loggly": {
                                "customer_token" : "tok",
                                "batch_max_size": 1,
                                "include_resp_body": true,
                                "include_resp_body_expr": [
                                    ["arg_bar", "==", "bar"]
                                ]
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
            -- this will include resp body
            local code, _, body = t("/opentracing?bar=bar", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)

        }
    }
--- response_body
passed
opentracing
--- grep_error_log eval
qr/message received: [ -~]+/
--- grep_error_log_out eval
qr/message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[tok\@41058 tag="apisix"] \{"apisix_latency":[\d.]*,"client_ip":"127\.0\.0\.1","latency":[\d.]*,"request":\{"headers":\{"content-type":"application\/x-www-form-urlencoded","host":"127\.0\.0\.1:1984","user-agent":"lua-resty-http\/[\d.]* \(Lua\) ngx_lua\/[\d]*"\},"method":"GET","querystring":\{"bar":"bar"\},"size":[\d]+,"uri":"\/opentracing\?bar=bar","url":"http:\/\/127\.0\.0\.1:1984\/opentracing\?bar=bar"\},"response":\{"body":"opentracing\\n","headers":\{"connection":"close","content-type":"text\/plain","server":"APISIX\/[\d.]+","transfer-encoding":"chunked"\},"size":[\d]*,"status":200\},"route_id":"1","server":\{"hostname":"[ -~]*","version":"[\d.]+"\},"service_id":"","start_time":[\d]*,"upstream":"127\.0\.0\.1:1982","upstream_latency":[\d]*\}/



=== TEST 10: collect log with include_resp_body_expr mismatch
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, _, body = t("/opentracing?foo=bar", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)

        }
    }
--- response_body
opentracing
--- grep_error_log eval
qr/message received: [ -~]+/
--- grep_error_log_out eval
qr/message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[tok\@41058 tag="apisix"] \{"apisix_latency":[\d.]*,"client_ip":"127\.0\.0\.1","latency":[\d.]*,"request":\{"headers":\{"content-type":"application\/x-www-form-urlencoded","host":"127\.0\.0\.1:1984","user-agent":"lua-resty-http\/[\d.]* \(Lua\) ngx_lua\/[\d]*"\},"method":"GET","querystring":\{"foo":"bar"\},"size":[\d]+,"uri":"\/opentracing\?foo=bar","url":"http:\/\/127\.0\.0\.1:1984\/opentracing\?foo=bar"\},"response":\{"headers":\{"connection":"close","content-type":"text\/plain","server":"APISIX\/[\d.]+","transfer-encoding":"chunked"\},"size":[\d]*,"status":200\},"route_id":"1","server":\{"hostname":"[ -~]*","version":"[\d.]+"\},"service_id":"","start_time":[\d]*,"upstream":"127\.0\.0\.1:1982","upstream_latency":[\d]*\}/



=== TEST 11: collect log with log_format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/loggly',
                 ngx.HTTP_PUT,
                 [[{
                        "host":"127.0.0.1",
                        "port": 8126,
                        "log_format":{
                            "host":"$host",
                            "client":"$remote_addr"
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)

            local code, _, body = t("/opentracing?foo=bar", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- response_body
passed
opentracing
--- grep_error_log eval
qr/message received: [ -~]+/
--- grep_error_log_out eval
qr/message received: <14>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[tok\@41058 tag="apisix"] \{"client":"[\d.]+","host":"[\d.]+","route_id":"1"\}/



=== TEST 12: loggly http protocol
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/loggly',
                 ngx.HTTP_PUT,
                 {
                    host = ngx.var.server_addr .. ":10420/loggly",
                    protocol = "http",
                    log_format = {
                        ["route_id"] = "$route_id",
                    }
                }
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
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
--- wait: 2
--- response_body
passed
opentracing
--- error_log
loggly body: {"route_id":"1"}
loggly tags: "apisix"



=== TEST 13: test setup for collecting syslog with severity based on http response code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "loggly": {
                                "customer_token" : "tok",
                                "batch_max_size": 1,
                                "severity_map": {
                                    "503": "ERR",
                                    "410": "ALERT"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:10420": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/loggly/*"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(body)

            local code, body = t('/apisix/admin/plugin_metadata/loggly',
                 ngx.HTTP_PUT,
                 [[{
                        "host":"127.0.0.1",
                        "port": 8126,
                        "log_format":{
                            "route_id": "$route_id"
                        }
                }]]
            )

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
passed



=== TEST 14: syslog PRIVAL 9 for type severity level ALERT
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, _ = t("/loggly/410", "GET")
            ngx.print(body)
        }
    }
--- response_body
expired link
--- grep_error_log eval
qr/message received: [ -~]+/
--- grep_error_log_out eval
qr/message received: <9>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[tok\@41058 tag="apisix"] \{"route_id":"1"\}/



=== TEST 15: syslog PRIVAL 11 for type severity level ERR
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body, _ = t("/loggly/503", "GET")
            ngx.print(body)
        }
    }
--- response_body
service temporarily unavailable
--- grep_error_log eval
qr/message received: [ -~]+/
--- grep_error_log_out eval
qr/message received: <11>1 [\d\-T:.]+Z [\d.]+ apisix [\d]+ - \[tok\@41058 tag="apisix"] \{"route_id":"1"\}/



=== TEST 16: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/loggly',
                 ngx.HTTP_PUT,
                 [[{
                        "host":"127.0.0.1",
                        "port": 8126,
                        "log_format":{
                            "client":"$remote_addr"
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "loggly": {
                                "customer_token" : "tok",
                                "log_format":{
                                    "host":"$host",
                                    "client":"$remote_addr"
                                },
                                "batch_max_size": 1,
                                "inactive_timeout": 1
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



=== TEST 17: hit
--- request
GET /opentracing?foo=bar
--- response_body
opentracing
--- wait: 0.5
--- grep_error_log eval
qr/message received: [ -~]+/
--- grep_error_log_out eval
qr/message received: <14>1 [\d\-T:.]+Z \w+ apisix [\d]+ - \[tok\@41058 tag="apisix"] \{"client":"[\d.]+","host":"\w+","route_id":"1"\}/
