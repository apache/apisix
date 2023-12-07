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

BEGIN {
    if ($ENV{TEST_EVENTS_MODULE} ne "lua-resty-worker-events") {
        $SkipReason = "Only fot lua-resty-worker-events events module";
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();
use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = <<_EOC_;
apisix:
    events:
        module: lua-resty-worker-events # fixed configuration
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests();

__DATA__

=== TEST 1: set route(passive)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 0,
                            "127.0.0.1:1": 1
                        },
                        "retries": 0,
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 100,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 100,
                                    "http_failures": 2
                                }
                            },]] .. [[
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 3
                                },
                                "unhealthy": {
                                    "http_statuses": [502],
                                    "http_failures": 1,
                                    "tcp_failures": 1
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



=== TEST 2: hit routes (two healthy nodes)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1) -- wait for sync

            local json_sort = require("toolkit.json")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/server_port"

            local ports_count = {}
            for i = 1, 6 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end

                local status = tostring(res.status)
                ports_count[status] = (ports_count[status] or 0) + 1
            end

            ngx.say(json_sort.encode(ports_count))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
{"200":5,"502":1}
--- error_log
(upstream#/apisix/routes/1) unhealthy HTTP increment (1/1)



=== TEST 3: set route(only passive)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 0,
                            "127.0.0.1:1": 1
                        },
                        "retries": 0,
                        "checks": {
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 3
                                },
                                "unhealthy": {
                                    "http_statuses": [502],
                                    "http_failures": 1,
                                    "tcp_failures": 1
                                }
                            }
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: object matches none of the required: [\"active\"] or [\"active\",\"passive\"]"}



=== TEST 4: set route(only active + active & passive)
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
                        "nodes": {
                            "127.0.0.1:1980": 0,
                            "127.0.0.1:1": 1
                        },
                        "retries": 0,
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 100,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 100,
                                    "http_failures": 2
                                }
                            }
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello_",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 0,
                            "127.0.0.1:1": 1
                        },
                        "retries": 0,
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 100,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 100,
                                    "http_failures": 2
                                }
                            },]] .. [[
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 3
                                },
                                "unhealthy": {
                                    "http_statuses": [502],
                                    "http_failures": 1,
                                    "tcp_failures": 1
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



=== TEST 5: only one route should have passive healthcheck
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json_sort = require("toolkit.json")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            local ports_count = {}
            local httpc = http.new()
            local res, err = httpc:request_uri(uri .. "/hello_")
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)

            -- only /hello_ has passive healthcheck
            local res, err = httpc:request_uri(uri .. "/hello")
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
        }
    }
--- request
GET /t
--- response_body
502
502
--- grep_error_log eval
qr/enabled healthcheck passive/
--- grep_error_log_out
enabled healthcheck passive



=== TEST 6: make sure passive healthcheck works (conf is not corrupted by the default value)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json_sort = require("toolkit.json")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            local ports_count = {}
            local httpc = http.new()
            local res, err = httpc:request_uri(uri .. "/hello")
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)

            local res, err = httpc:request_uri(uri .. "/hello_")
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
        }
    }
--- request
GET /t
--- response_body
502
502
--- grep_error_log eval
qr/\[healthcheck\] \([^)]+\) unhealthy HTTP increment/
--- grep_error_log_out
[healthcheck] (upstream#/apisix/routes/2) unhealthy HTTP increment
