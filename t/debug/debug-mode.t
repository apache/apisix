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

our $debug_config = t::APISIX::read_file("conf/debug.yaml");
$debug_config =~ s/basic:\n  enable: false/basic:\n  enable: true/;

run_tests;

__DATA__

=== TEST 1: loaded plugin
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
loaded plugin and sort by priority: 23000 name: real-ip
loaded plugin and sort by priority: 22000 name: client-control
loaded plugin and sort by priority: 12015 name: request-id
loaded plugin and sort by priority: 12011 name: zipkin
loaded plugin and sort by priority: 12000 name: ext-plugin-pre-req
loaded plugin and sort by priority: 11000 name: fault-injection
loaded plugin and sort by priority: 10000 name: serverless-pre-function
loaded plugin and sort by priority: 4000 name: cors
loaded plugin and sort by priority: 3000 name: ip-restriction
loaded plugin and sort by priority: 2990 name: referer-restriction
loaded plugin and sort by priority: 2900 name: uri-blocker
loaded plugin and sort by priority: 2800 name: request-validation
loaded plugin and sort by priority: 2600 name: multi-auth
loaded plugin and sort by priority: 2599 name: openid-connect
loaded plugin and sort by priority: 2555 name: wolf-rbac
loaded plugin and sort by priority: 2530 name: hmac-auth
loaded plugin and sort by priority: 2520 name: basic-auth
loaded plugin and sort by priority: 2510 name: jwt-auth
loaded plugin and sort by priority: 2500 name: key-auth
loaded plugin and sort by priority: 2400 name: consumer-restriction
loaded plugin and sort by priority: 2000 name: authz-keycloak
loaded plugin and sort by priority: 1085 name: proxy-cache
loaded plugin and sort by priority: 1010 name: proxy-mirror
loaded plugin and sort by priority: 1008 name: proxy-rewrite
loaded plugin and sort by priority: 1005 name: api-breaker
loaded plugin and sort by priority: 1003 name: limit-conn
loaded plugin and sort by priority: 1002 name: limit-count
loaded plugin and sort by priority: 1001 name: limit-req
loaded plugin and sort by priority: 995 name: gzip
loaded plugin and sort by priority: 990 name: server-info
loaded plugin and sort by priority: 966 name: traffic-split
loaded plugin and sort by priority: 900 name: redirect
loaded plugin and sort by priority: 899 name: response-rewrite
loaded plugin and sort by priority: 506 name: grpc-transcode
loaded plugin and sort by priority: 500 name: prometheus
loaded plugin and sort by priority: 412 name: echo
loaded plugin and sort by priority: 410 name: http-logger
loaded plugin and sort by priority: 406 name: sls-logger
loaded plugin and sort by priority: 405 name: tcp-logger
loaded plugin and sort by priority: 403 name: kafka-logger
loaded plugin and sort by priority: 402 name: rocketmq-logger
loaded plugin and sort by priority: 401 name: syslog
loaded plugin and sort by priority: 400 name: udp-logger
loaded plugin and sort by priority: 398 name: clickhouse-logger
loaded plugin and sort by priority: 0 name: example-plugin
loaded plugin and sort by priority: -2000 name: serverless-post-function
loaded plugin and sort by priority: -3000 name: ext-plugin-post-req



=== TEST 2: set route(no plugin)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "uri": "/hello",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: hit routes
--- debug_config eval: $::debug_config
--- request
GET /hello
--- response_body
hello world
--- response_headers
Apisix-Plugins: no plugin



=== TEST 4: set route(one plugin)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            },
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: hit routes
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local ngx_re = require("ngx.re")
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                    method = "GET",
                })
            local debug_header = res.headers["Apisix-Plugins"]
            local arr = ngx_re.split(debug_header, ", ")
            local hash = {}
            for i, v in ipairs(arr) do
                hash[v] = true
            end
            ngx.status = res.status
            ngx.say(json.encode(hash))
        }
    }
--- request
GET /t
--- response_body
{"limit-conn":true,"limit-count":true}



=== TEST 6: global rule, header sent
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "status_code": 200,
                            "body": "yes\n"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 7: hit routes
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local ngx_re = require("ngx.re")
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                    method = "GET",
                })
            local debug_header = res.headers["Apisix-Plugins"]
            local arr = ngx_re.split(debug_header, ", ")
            local hash = {}
            for i, v in ipairs(arr) do
                hash[v] = true
            end
            ngx.status = res.status
            ngx.say(json.encode(hash))
        }
    }
--- request
GET /t
--- response_body
{"limit-conn":true,"limit-count":true,"response-rewrite":true}
--- error_log
Apisix-Plugins: response-rewrite



=== TEST 8: clear global routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 9: set stream route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "server_port": 1985,
                    "plugins": {
                        "mqtt-proxy": {
                            "protocol_name": "MQTT",
                            "protocol_level": 4
                        }
                    },
                    "upstream": {
                        "type": "chash",
                        "key": "mqtt_client_id",
                        "nodes": [
                            {
                                "host": "127.0.0.1",
                                "port": 1995,
                                "weight": 1
                            }
                        ]
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: hit route
--- debug_config eval: $::debug_config
--- stream_request eval
"\x10\x0f\x00\x04\x4d\x51\x54\x54\x04\x02\x00\x3c\x00\x03\x66\x6f\x6f"
--- stream_response
hello world
--- error_log
mqtt client id: foo while prereading client data
