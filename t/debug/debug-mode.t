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

sub read_file($) {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $yaml_config = read_file("conf/config.yaml");
$yaml_config =~ s/node_listen: 9080/node_listen: 1984/;
$yaml_config =~ s/enable_debug: false/enable_debug: true/;

run_tests;

__DATA__

=== TEST 1: loaded plugin
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            ngx.say("done")
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
done
--- grep_error_log eval
qr/loaded plugin and sort by priority: [-\d]+ name: [\w-]+/
--- grep_error_log_out
loaded plugin and sort by priority: 11010 name: request-id
loaded plugin and sort by priority: 11000 name: fault-injection
loaded plugin and sort by priority: 10000 name: serverless-pre-function
loaded plugin and sort by priority: 4010 name: batch-requests
loaded plugin and sort by priority: 4000 name: cors
loaded plugin and sort by priority: 3000 name: ip-restriction
loaded plugin and sort by priority: 2900 name: uri-blocker
loaded plugin and sort by priority: 2800 name: request-validation
loaded plugin and sort by priority: 2599 name: openid-connect
loaded plugin and sort by priority: 2555 name: wolf-rbac
loaded plugin and sort by priority: 2520 name: basic-auth
loaded plugin and sort by priority: 2510 name: jwt-auth
loaded plugin and sort by priority: 2500 name: key-auth
loaded plugin and sort by priority: 2400 name: consumer-restriction
loaded plugin and sort by priority: 2000 name: authz-keycloak
loaded plugin and sort by priority: 1010 name: proxy-mirror
loaded plugin and sort by priority: 1009 name: proxy-cache
loaded plugin and sort by priority: 1008 name: proxy-rewrite
loaded plugin and sort by priority: 1003 name: limit-conn
loaded plugin and sort by priority: 1002 name: limit-count
loaded plugin and sort by priority: 1001 name: limit-req
loaded plugin and sort by priority: 1000 name: node-status
loaded plugin and sort by priority: 900 name: redirect
loaded plugin and sort by priority: 899 name: response-rewrite
loaded plugin and sort by priority: 506 name: grpc-transcode
loaded plugin and sort by priority: 500 name: prometheus
loaded plugin and sort by priority: 412 name: echo
loaded plugin and sort by priority: 410 name: http-logger
loaded plugin and sort by priority: 405 name: tcp-logger
loaded plugin and sort by priority: 403 name: kafka-logger
loaded plugin and sort by priority: 401 name: syslog
loaded plugin and sort by priority: 400 name: udp-logger
loaded plugin and sort by priority: 0 name: example-plugin
loaded plugin and sort by priority: -1000 name: zipkin
loaded plugin and sort by priority: -1100 name: skywalking
loaded plugin and sort by priority: -2000 name: serverless-post-function



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
--- no_error_log
[error]



=== TEST 3: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- response_headers
Apisix-Plugins: no plugin
--- no_error_log
[error]



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
--- no_error_log
[error]



=== TEST 5: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- response_headers
Apisix-Plugins: limit-conn, limit-count
--- no_error_log
[error]
