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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;
    my $port = $ENV{TEST_NGINX_SERVER_PORT};

    my $config = $block->config // <<_EOC_;
    location /access_root_dir {
        content_by_lua_block {
            local httpc = require "resty.http"
            local hc = httpc:new()

            local res, err = hc:request_uri('http://127.0.0.1:$port/limit_conn')
            if res then
                ngx.exit(res.status)
            end
        }
    }

    location /test_concurrency {
        content_by_lua_block {
            local reqs = {}
            for i = 1, 10 do
                reqs[i] = { "/access_root_dir" }
            end
            local resps = { ngx.location.capture_multi(reqs) }
            for i, resp in ipairs(resps) do
                ngx.say(resp.status)
            end
        }
    }
_EOC_

    $block->set_value("config", $config);
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-conn")
            local ok, err = plugin.check_schema({conn = 1, burst = 0, default_conn_delay = 0.1, rejected_code = 503, key = 'remote_addr'})
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



=== TEST 2: wrong value of key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-conn")
            local ok, err = plugin.check_schema({conn = 1, default_conn_delay = 0.1, rejected_code = 503, key = 'remote_addr'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "burst" is required
done
--- no_error_log
[error]



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
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
                        "uri": "/limit_conn"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
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
                            "uri": "/limit_conn"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 4: not exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
200
200
200
200
200
200
200
--- no_error_log
[error]



=== TEST 5: update plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 2,
                                "burst": 1,
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
                        "uri": "/limit_conn"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-conn": {
                                    "conn": 2,
                                    "burst": 1,
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
                            "uri": "/limit_conn"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 6: exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
503
503
503
503
503
503
503
--- no_error_log
[error]



=== TEST 7: update plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 5,
                                "burst": 1,
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
                        "uri": "/limit_conn"
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



=== TEST 8: exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
200
200
200
503
503
503
503
--- no_error_log
[error]



=== TEST 9: invalid route: missing key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "burst": 1,
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
                        "uri": "/limit_conn"
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
{"error_msg":"failed to check the configuration of plugin limit-conn err: property \"conn\" is required"}
--- no_error_log
[error]



=== TEST 10: invalid route: wrong conn
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                    "conn": -1,
                                    "burst": 1,
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
                        "uri": "/limit_conn"
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
{"error_msg":"failed to check the configuration of plugin limit-conn err: property \"conn\" validation failed: expected -1 to be strictly greater than 0"}
--- no_error_log
[error]



=== TEST 11: invalid service: missing key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                    "burst": 1,
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
{"error_msg":"failed to check the configuration of plugin limit-conn err: property \"conn\" is required"}
--- no_error_log
[error]



=== TEST 12: invalid service: wrong count
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": -1,
                                "burst": 1,
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
{"error_msg":"failed to check the configuration of plugin limit-conn err: property \"conn\" validation failed: expected -1 to be strictly greater than 0"}
--- no_error_log
[error]



=== TEST 13: disable plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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



=== TEST 14: exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
200
200
200
200
200
200
200
--- no_error_log
[error]



=== TEST 15: set route(key: server_addr)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "server_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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



=== TEST 16: key: http_x_real_ip
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 5,
                                "burst": 1,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "http_x_real_ip"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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



=== TEST 17: exceeding the burst (X-Real-IP)
--- config
location /access_root_dir {
    content_by_lua_block {
        local port = ngx.var.server_port
        local httpc = require "resty.http"
        local hc = httpc:new()

        local res, err = hc:request_uri('http://127.0.0.1:' .. port .. '/limit_conn', {
            keepalive = false,
            headers = {["X-Real-IP"] = "10.10.10.1"}
        })
        if res then
            ngx.exit(res.status)
        end
    }
}

location /test_concurrency {
    content_by_lua_block {
        local reqs = {}
        for i = 1, 10 do
            reqs[i] = { "/access_root_dir" }
        end
        local resps = { ngx.location.capture_multi(reqs) }
        for i, resp in ipairs(resps) do
            ngx.say(resp.status)
        end
    }
}
--- more_headers
X-Real-IP: 10.0.0.1
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
200
200
200
503
503
503
503
--- error_log
limit key: 10.10.10.1route



=== TEST 18: key: http_x_forwarded_for
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 5,
                                "burst": 1,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "http_x_forwarded_for"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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



=== TEST 19: exceeding the burst(X-Forwarded-For)
--- config
location /access_root_dir {
    content_by_lua_block {
        local port = ngx.var.server_port
        local httpc = require "resty.http"
        local hc = httpc:new()

        local res, err = hc:request_uri('http://127.0.0.1:' .. port .. '/limit_conn', {
            keepalive = false,
            headers = {["X-Forwarded-For"] = "10.10.10.2"}
        })
        if res then
            ngx.exit(res.status)
        end
    }
}

location /test_concurrency {
    content_by_lua_block {
        local reqs = {}
        for i = 1, 10 do
            reqs[i] = { "/access_root_dir" }
        end
        local resps = { ngx.location.capture_multi(reqs) }
        for i, resp in ipairs(resps) do
            ngx.say(resp.status)
        end
    }
}
--- more_headers
X-Real-IP: 10.0.0.1
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
200
200
200
503
503
503
503
--- error_log
limit key: 10.10.10.2route



=== TEST 20: default rejected_code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-conn": {
                                    "rejected_code": 503
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/limit_conn"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 21: set global rule with conn = 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-conn": {
                            "conn": 2,
                            "burst": 1,
                            "default_conn_delay": 0.1,
                            "key": "remote_addr"
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
--- no_error_log
[error]



=== TEST 22: exceeding the burst of global rule
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
503
503
503
503
503
503
503
--- no_error_log
[error]



=== TEST 23: delete global rule
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
--- no_error_log
[error]



=== TEST 24: not exceeding the burst
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
200
200
200
200
200
200
200
--- no_error_log
[error]



=== TEST 25: invalid schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-conn")
            local cases = {
                {conn = 0, burst = 0, default_conn_delay = 0.1, rejected_code = 503, key = 'remote_addr'},
                {conn = 1, burst = 0, default_conn_delay = 0, rejected_code = 503, key = 'remote_addr'},
            }
            for _, c in ipairs(cases) do
                local ok, err = plugin.check_schema(c)
                if not ok then
                    ngx.say(err)
                end
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "conn" validation failed: expected 0 to be strictly greater than 0
property "default_conn_delay" validation failed: expected 0 to be strictly greater than 0
done
--- no_error_log
[error]



=== TEST 26: create consumer and bind key-auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "consumer_jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
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
--- no_error_log
[error]



=== TEST 27: create route and enable plugin 'key-auth'
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "key-auth": {},
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "consumer_name"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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



=== TEST 28: not exceeding the burst
--- config
    location /access_root_dir {
        content_by_lua_block {
            local port = ngx.var.server_port
            local httpc = require "resty.http"
            local hc = httpc:new()

            local res, err = hc:request_uri('http://127.0.0.1:' .. port .. '/limit_conn', {
                headers = {["apikey"] = "auth-jack"}
            })
            if res then
                ngx.exit(res.status)
            end
        }
    }

    location /test_concurrency {
        content_by_lua_block {
            local reqs = {}
            for i = 1, 10 do
                reqs[i] = { "/access_root_dir" }
            end
            local resps = { ngx.location.capture_multi(reqs) }
            for i, resp in ipairs(resps) do
                ngx.say(resp.status)
            end
        }
    }
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
200
200
200
200
200
200
200
--- error_log_like eval
qr/limit key: consumer_jackroute&consumer\d+/



=== TEST 29: update plugin "limit-conn" configuration "conn" and "burst"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "key-auth": {},
                            "limit-conn": {
                                "conn": 2,
                                "burst": 1,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "consumer_name"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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



=== TEST 30: exceeding the burst
--- config
    location /access_root_dir {
        content_by_lua_block {
            local port = ngx.var.server_port
            local httpc = require "resty.http"
            local hc = httpc:new()

            local res, err = hc:request_uri('http://127.0.0.1:' .. port .. '/limit_conn', {
                headers = {["apikey"] = "auth-jack"}
            })
            if res then
                ngx.exit(res.status)
            end
        }
    }

    location /test_concurrency {
        content_by_lua_block {
            local reqs = {}
            for i = 1, 10 do
                reqs[i] = { "/access_root_dir" }
            end
            local resps = { ngx.location.capture_multi(reqs) }
            for i, resp in ipairs(resps) do
                ngx.say(resp.status)
            end
        }
    }
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
503
503
503
503
503
503
503
--- error_log_like eval
qr/limit key: consumer_jackroute&consumer\d+/



=== TEST 31: plugin limit-conn uses the wrong value of key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-conn")
            local ok, err = plugin.check_schema({
                conn = 1,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = 'consumer_name'
                    })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "burst" is required
done
--- no_error_log
[error]



=== TEST 32: enable plugin: conn=1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-conn": {
                            "conn": 1,
                            "burst": 0,
                            "default_conn_delay": 0.3,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "allow_degradation": true
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



=== TEST 33: hit route and should not be limited
--- pipelined_requests eval
[
    "GET /hello", "GET /hello", "GET /hello",
    "GET /hello", "GET /hello", "GET /hello",
]
--- timeout: 10s
--- error_code eval
[
    200, 200, 200,
    200, 200, 200
]
--- no_error_log
[error]



=== TEST 34: invalid route: wrong allow_degradation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                    "conn": 1,
                                    "burst": 1,
                                    "default_conn_delay": 0.1,
                                    "rejected_code": 503,
                                    "key": "remote_addr",
                                    "allow_degradation": "true1"
                                }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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
{"error_msg":"failed to check the configuration of plugin limit-conn err: property \"allow_degradation\" validation failed: wrong type: expected boolean, got string"}
--- no_error_log
[error]
