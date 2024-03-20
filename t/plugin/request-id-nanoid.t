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

=== TEST 1: check config with algorithm nanoid
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "algorithm": "nanoid",
                                "nanoid": {
                                    "char_set": "abcdefg",
                                    "length": 36
                                }
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



=== TEST 2: add plugin with algorithm nanoid (set automatic default)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
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
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: hit
--- request
GET /opentracing



=== TEST 4: add plugin with algorithm nanoid
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
                                "algorithm": "nanoid",
                                "nanoid": {}
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
                    if #id ~= 21 then
                        ngx.say(id)
                        ngx.say("incorrect length for id")
                        return
                    end
                    local start, en = string.find(id, '[a-zA-Z0-9_\\-]*')
                    if start ~= 1 or en ~= 21 then
                        ngx.say("incorrect char set for id")
                        ngx.say(id)
                        return
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
