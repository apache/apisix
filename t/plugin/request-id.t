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

log_level('debug');
worker_connections(1024);
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: wrong type
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({include_in_response = "bad_type"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "include_in_response" validation failed: wrong type: expected boolean, got string
done



=== TEST 3: add plugin with include_in_response true (default true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
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



=== TEST 4: check for request id in response header (default header name)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["X-Request-Id"] then
                ngx.say("request header present")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
request header present



=== TEST 5: check for unique id
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = {}
            local ids = {}
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function()
                    local httpc = http.new()
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
                    local res, err = httpc:request_uri(uri,
                        {
                            method = "GET",
                            headers = {
                                ["Content-Type"] = "application/json",
                            }
                        }
                    )
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end

                    local id = res.headers["X-Request-Id"]
                    if not id then
                        return -- ignore if the data is not synced yet.
                    end

                    if ids[id] == true then
                        ngx.say("ids not unique")
                        return
                    end
                    ids[id] = true
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end

            ngx.say("true")
        }
    }
--- wait: 5
--- response_body
true



=== TEST 6: add plugin with custom header name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "header_name": "Custom-Header-Name"
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



=== TEST 7: check for request id in response header (custom header name)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["Custom-Header-Name"] then
                ngx.say("request header present")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
request header present



=== TEST 8: add plugin with include_in_response false (default true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "include_in_response": false
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



=== TEST 9: check for request id is not present in the response header
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if not res.headers["X-Request-Id"] then
                ngx.say("request header not present")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
request header not present



=== TEST 10: add plugin with custom header name in global rule and add plugin with default header name in specific route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                     [[{
                        "plugins": {
                            "request-id": {
                                "header_name":"Custom-Header-Name"
                            }
                        }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "request-id": {
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
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: check for multiple request-ids in the response header are different
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["X-Request-Id"] ~= res.headers["Custom-Header-Name"] then
                ngx.say("X-Request-Id and Custom-Header-Name are different")
            else
                ngx.say("failed")
            end
        }
    }
--- response_body
X-Request-Id and Custom-Header-Name are different



=== TEST 12: wrong algorithm type
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({algorithm = "bad_algorithm"})
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "algorithm" validation failed: matches none of the enum values
done



=== TEST 13: add plugin with include_in_response true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "include_in_response": true
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



=== TEST 14: echo back the client's header if given
--- request
GET /opentracing
--- more_headers
X-Request-ID: 123
--- response_headers
X-Request-ID: 123



=== TEST 15: add plugin with algorithm nanoid (default uuid)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local v = {}
            local ids = {}
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "algorithm": "nanoid"
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
                ngx.say("algorithm nanoid is error")
            end
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function()
                    local httpc = http.new()
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
                    local res, err = httpc:request_uri(uri,
                        {
                            method = "GET",
                            headers = {
                                ["Content-Type"] = "application/json",
                            }
                        }
                    )
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                    local id = res.headers["X-Request-Id"]
                    if not id then
                        return -- ignore if the data is not synced yet.
                    end
                    if ids[id] == true then
                        ngx.say("ids not unique")
                        return
                    end
                    ids[id] = true
                end, i))
                table.insert(v, th)
            end
            for i, th in ipairs(v) do
                ngx.thread.wait(th)
            end
            ngx.say("true")
        }
    }
--- wait: 5
--- response_body
true
