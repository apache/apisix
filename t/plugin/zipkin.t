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

repeat_each(2);
no_long_string();
no_root_location();
log_level("info");
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1', sample_ratio = 0.001})
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



=== TEST 2: default value of sample_ratio
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1'})
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
--- SKIP



=== TEST 3: wrong value of ratio
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1', sample_ratio = -0.1})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "sample_ratio" validation failed: expected -0.1 to be greater than 1e-05
done
--- no_error_log
[error]



=== TEST 4: wrong value of ratio
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1', sample_ratio = 2})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "sample_ratio" validation failed: expected 2 to be smaller than 1
done
--- no_error_log
[error]



=== TEST 5: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1982/mock_zipkin?server_addr=127.0.0.1",
                                "sample_ratio": 1,
                                "service_name": "APISIX"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "zipkin": {
                                    "endpoint": "http://127.0.0.1:1982/mock_zipkin?server_addr=127.0.0.1",
                                    "sample_ratio": 1,
                                    "service_name":"APISIX"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
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



=== TEST 6: tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/\[info\].*/
--- grep_error_log_out eval
qr{report2endpoint ok}



=== TEST 7: change sample ratio
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1982/mock_zipkin",
                                "sample_ratio": 0.00001
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "zipkin": {
                                    "endpoint": "http://127.0.0.1:1982/mock_zipkin",
                                    "sample_ratio": 0.00001
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
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



=== TEST 8: not tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing
--- no_error_log
report2endpoint ok



=== TEST 9: disabled
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
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
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



=== TEST 10: not tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing
--- no_error_log
report2endpoint ok



=== TEST 11: set plugin with external ip address
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1982/mock_zipkin?server_addr=1.2.3.4",
                                "sample_ratio": 1,
                                "service_name": "apisix",
                                "server_addr": "1.2.3.4"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 12: tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/\[info\].*/
--- grep_error_log_out eval
qr{report2endpoint ok}



=== TEST 13: sanity server_addr
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({
                endpoint = 'http://127.0.0.1',
                sample_ratio = 0.001,
                server_addr = 'badip'
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
property "server_addr" validation failed: failed to match pattern "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$" with "badip"
--- no_error_log
[error]



=== TEST 14: check not error with limit count
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1982/mock_zipkin?server_addr=127.0.0.1",
                                "sample_ratio": 1,
                                "service_name": "APISIX"
                            },
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 403,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /t", "GET /opentracing", "GET /opentracing", "GET /opentracing"]
--- error_code eval
[200, 200, 200, 403]
--- no_error_log
[error]
