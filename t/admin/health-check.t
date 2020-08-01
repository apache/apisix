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
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    my $init_by_lua_block = <<_EOC_;
    require "resty.core"
    apisix = require("apisix")
    apisix.http_init()

    json = require("cjson.safe")
    req_data = json.decode([[{
        "methods": ["GET"],
        "upstream": {
            "nodes": {
                "127.0.0.1:8080": 1
            },
            "type": "roundrobin",
            "checks": {}
        },
        "uri": "/index.html"
    }]])
    exp_data = {
        node = {
            value = req_data,
            key = "/apisix/routes/1",
        },
        action = "set",
    }
_EOC_

    $block->set_value("init_by_lua_block", $init_by_lua_block);
});

run_tests;

__DATA__

=== TEST 1: active
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "http_path": "/status",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    },
                    "unhealthy": {
                        "interval": 1,
                        "http_failures": 2
                    }
                }
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: passive
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "http_path": "/status",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    }
                },
                "passive": {
                    "healthy": {
                        "http_statuses": [200, 201],
                        "successes": 1
                    },
                    "unhealthy": {
                        "http_statuses": [500],
                        "http_failures": 2
                    }
                }
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: invalid route: active.healthy.successes counter exceed maximum value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "healthy": {
                        "successes": 255
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: property \"active\" validation failed: property \"healthy\" validation failed: property \"successes\" validation failed: expected 255 to be smaller than 254"}
--- no_error_log
[error]



=== TEST 4: invalid route: active.healthy.successes counter below the minimum value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "healthy": {
                        "successes": 0
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: property \"active\" validation failed: property \"healthy\" validation failed: property \"successes\" validation failed: expected 0 to be greater than 1"}
--- no_error_log
[error]



=== TEST 5: invalid route: wrong passive.unhealthy.http_statuses
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "passive": {
                    "unhealthy": {
                        "http_statuses": [500, 600]
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: property \"passive\" validation failed: property \"unhealthy\" validation failed: property \"http_statuses\" validation failed: failed to validate item 2: expected 600 to be smaller than 599"}
--- no_error_log
[error]



=== TEST 6: invalid route: wrong active.type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "type": "udp"
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: property \"active\" validation failed: property \"type\" validation failed: matches non of the enum values"}
--- no_error_log
[error]



=== TEST 7: invalid route: duplicate items in active.healthy.http_statuses
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "healthy": {
                        "http_statuses": [200, 200]
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: property \"active\" validation failed: property \"healthy\" validation failed: property \"http_statuses\" validation failed: expected unique items but items 2 and 1 are equal"}
--- no_error_log
[error]



=== TEST 8: invalid route: active.unhealthy.http_failure is a floating point value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "unhealthy": {
                        "http_failures": 3.1
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: property \"active\" validation failed: property \"unhealthy\" validation failed: property \"http_failures\" validation failed: wrong type: expected integer, got number"}
--- no_error_log
[error]



=== TEST 9: valid req_headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "http_path": "/status",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    },
                    "req_headers": ["User-Agent: curl/7.29.0"]
                }
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 10: multiple request headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "http_path": "/status",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    },
                    "req_headers": ["User-Agent: curl/7.29.0", "Accept: */*"]
                }
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: invalid req_headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "http_path": "/status",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    },
                    "req_headers": ["User-Agent: curl/7.29.0", 2233]
                }
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: property \"active\" validation failed: property \"req_headers\" validation failed: failed to validate item 2: wrong type: expected string, got number"}
--- no_error_log
[error]



=== TEST 12: only passive
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "passive": {
                    "healthy": {
                        "http_statuses": [200, 201],
                        "successes": 1
                    },
                    "unhealthy": {
                        "http_statuses": [500],
                        "http_failures": 2
                    }
                }
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: object matches none of the requireds: [\"active\"] or [\"active\",\"passive\"]"}
--- no_error_log
[error]



=== TEST 13: number type timeout
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "http_path": "/status",
                    "host": "foo.com",
                    "timeout": 1.01,
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    },
                    "unhealthy": {
                        "interval": 1,
                        "http_failures": 2
                    }
                }
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
