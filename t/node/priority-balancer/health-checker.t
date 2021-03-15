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
log_level('info');
no_root_location();
worker_connections(1024);
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ($block->apisix_yaml) {
        if (!$block->yaml_config) {
            my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

            $block->set_value("yaml_config", $yaml_config);
        }

        my $route = <<_EOC_;
routes:
    -
    upstream_id: 1
    uris:
        - /hello
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $route);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: all are down detected by health checker
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 123
        - host: 127.0.0.2
          port: 1979
          weight: 3
          priority: -1
    checks:
        active:
            http_path: "/status"
            healthy:
                interval: 1
                successes: 1
            unhealthy:
                interval: 1
                http_failures: 1
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local httpc = http.new()
            httpc:request_uri(uri, {method = "GET"})
            ngx.sleep(2.5)
            -- still use all nodes
            httpc:request_uri(uri, {method = "GET"})
        }
    }
--- request
GET /t
--- error_log
connect() failed
unhealthy TCP increment (2/2) for '(127.0.0.1:1979)
unhealthy TCP increment (2/2) for '(127.0.0.2:1979)
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979



=== TEST 2: use priority as backup (setup rule)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": [
                                {"host": "127.0.0.1", "port": 1979, "weight": 2000},
                                {"host": "127.0.0.1", "port": 1980,
                                 "weight": 1, "priority": -1}
                            ],
                            "checks": {
                                "active": {
                                    "http_path": "/status",
                                    "healthy": {
                                        "interval": 1,
                                        "successes": 1
                                    },
                                    "unhealthy": {
                                        "interval": 1,
                                        "http_failures": 1
                                    }
                                }
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



=== TEST 3: use priority as backup
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local httpc = http.new()
            httpc:request_uri(uri, {method = "GET"})
            ngx.sleep(2.5)
            httpc:request_uri(uri, {method = "GET"})
        }
    }
--- request
GET /t
--- error_log
connect() failed
unhealthy TCP increment (2/2) for '(127.0.0.1:1979)
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.1:1980
proxy request to 127.0.0.1:1980
