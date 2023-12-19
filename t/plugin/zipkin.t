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



=== TEST 2: wrong value of ratio
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
property "sample_ratio" validation failed: expected -0.1 to be at least 1e-05
done



=== TEST 3: wrong value of ratio
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
property "sample_ratio" validation failed: expected 2 to be at most 1
done



=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1980/mock_zipkin?server_addr=127.0.0.1",
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



=== TEST 5: tiger zipkin
--- request
GET /opentracing
--- wait: 10



=== TEST 6: change sample ratio
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:9999/mock_zipkin",
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



=== TEST 7: not tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing



=== TEST 8: disabled
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



=== TEST 9: not tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing



=== TEST 10: set plugin with external ip address
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1980/mock_zipkin?server_addr=1.2.3.4",
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



=== TEST 11: tiger zipkin
--- request
GET /opentracing
--- wait: 10



=== TEST 12: sanity server_addr
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



=== TEST 13: check zipkin headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:9999/mock_zipkin",
                                "sample_ratio": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 14: set x-b3-sampled if sampled
--- request
GET /echo
--- response_headers
x-b3-sampled: 1



=== TEST 15: don't sample if disabled
--- request
GET /echo
--- more_headers
x-b3-sampled: 0
--- response_headers
x-b3-sampled: 0



=== TEST 16: don't sample if disabled (old way)
--- request
GET /echo
--- more_headers
x-b3-sampled: false
--- response_headers
x-b3-sampled: 0



=== TEST 17: sample according to the header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:9999/mock_zipkin",
                                "sample_ratio": 0.00001
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
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



=== TEST 18: don't sample by default
--- request
GET /echo
--- response_headers
x-b3-sampled: 0



=== TEST 19: sample if needed
--- request
GET /echo
--- more_headers
x-b3-sampled: 1
--- response_headers
x-b3-sampled: 1



=== TEST 20: sample if debug
--- request
GET /echo
--- more_headers
x-b3-flags: 1
--- response_headers
x-b3-sampled: 1



=== TEST 21: sample if needed (old way)
--- request
GET /echo
--- more_headers
x-b3-sampled: true
--- response_headers
x-b3-sampled: 1



=== TEST 22: don't cache the per-req sample ratio
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/echo"
            -- force to trace
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ['x-b3-sampled'] = 1
                }
            })
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.headers['x-b3-sampled'])

            -- force not to trace
            local res, err = httpc:request_uri(uri, {
                method = "GET",
                headers = {
                    ['x-b3-sampled'] = 0
                }
            })
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.headers['x-b3-sampled'])
        }
    }
--- request
GET /t
--- response_body
1
0



=== TEST 23: no error in log phase while b3 header invalid
--- request
GET /echo
--- more_headers
b3: abc
--- no_error_log
[error]