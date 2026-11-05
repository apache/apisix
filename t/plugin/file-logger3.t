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

no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: configure response-phase filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            os.remove("file-logger-phase-filter.log")

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "file-logger": {
                            "path": "file-logger-phase-filter.log",
                            "log_format": {
                                "status": "$status",
                                "upstream_status": "$upstream_status"
                            },
                            "_meta": {
                                "filter": [
                                    ["upstream_status", "==", "201"]
                                ]
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
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



=== TEST 2: reevaluate filter after upstream response
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/specific_status", ngx.HTTP_GET, nil, nil,
                { ["x-test-upstream-status"] = "201" })

            local file, err = io.open("file-logger-phase-filter.log", "r")
            if not file then
                core.log.error("failed to open log file: ", err)
                ngx.status = 500
                return
            end

            local entry = core.json.decode(file:read("*l"))
            file:close()

            ngx.status = code
            ngx.say("status: ", entry.status)
            ngx.say("upstream_status: ", entry.upstream_status)
        }
    }
--- error_code: 201
--- response_body
status: 201
upstream_status: 201



=== TEST 3: capture request and response bodies with a response filter
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local path = "file-logger-filter-bodies.log"
            os.remove(path)
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                },
                plugins = {
                    ["file-logger"] = {
                        path = path,
                        include_req_body = true,
                        include_resp_body = true,
                        _meta = {filter = {{"upstream_status", "==", "200"}}}
                    }
                }
            })
            assert(code < 300, body)
            local res = assert(require("resty.http").new():request_uri(
                "http://127.0.0.1:1984/hello", {
                    method = "POST",
                    body = "request payload"
                }))
            assert(res.status == 200, res.body)
            local file = assert(io.open(path, "r"))
            local entry = assert(core.json.decode(file:read("*l")))
            assert(file:read("*l") == nil)
            file:close()
            ngx.say(entry.request.body)
            ngx.print(entry.response.body)
        }
    }
--- response_body
request payload
hello world



=== TEST 4: a false log filter does not emit an entry after body capture
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = "file-logger-filter-bodies.log"
            os.remove(path)
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                },
                plugins = {
                    ["file-logger"] = {
                        path = path,
                        include_req_body = true,
                        include_resp_body = true,
                        _meta = {filter = {{"status", "==", 500}}}
                    }
                }
            })
            assert(code < 300, body)
            local res = assert(require("resty.http").new():request_uri(
                "http://127.0.0.1:1984/hello", {
                    method = "POST",
                    body = "excluded payload"
                }))
            ngx.say(res.status)
            local file = io.open(path, "r")
            if file then
                ngx.say(file:read("*a"))
                file:close()
            else
                ngx.say("no entry")
            end
        }
    }
--- response_body
200
no entry



=== TEST 5: configure a filtered logger and an unfiltered logger
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            os.remove("file-logger-status-cache.log")

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:1980/log",
                            "_meta": {
                                "filter": [
                                    ["status", "==", 404]
                                ]
                            }
                        },
                        "file-logger": {
                            "path": "file-logger-status-cache.log",
                            "log_format": {
                                "status": "$status"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
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



=== TEST 6: filtered logger does not cache status for another logger
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/specific_status", ngx.HTTP_GET, nil, nil,
                { ["x-test-upstream-status"] = "201" })

            local file, err = io.open("file-logger-status-cache.log", "r")
            if not file then
                core.log.error("failed to open log file: ", err)
                ngx.status = 500
                return
            end

            local entry = core.json.decode(file:read("*l"))
            file:close()

            ngx.status = code
            ngx.say("status: ", entry.status)
        }
    }
--- error_code: 201
--- response_body
status: 201



=== TEST 7: an excluded logger does not supply a body to another logger
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local path = "file-logger-body-isolation.log"
            os.remove(path)
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                },
                plugins = {
                    ["http-logger"] = {
                        uri = "http://127.0.0.1:1980/log",
                        include_resp_body = true,
                        _meta = {filter = {{"status", "==", 500}}}
                    },
                    ["file-logger"] = {
                        path = path,
                        include_resp_body = true,
                        include_resp_body_expr = {{"status", "==", 500}}
                    }
                }
            })
            assert(code < 300, body)
            local res = assert(require("resty.http").new():request_uri(
                "http://127.0.0.1:1984/hello"))
            assert(res.status == 200, res.body)
            local file = assert(io.open(path, "r"))
            local entry = assert(core.json.decode(file:read("*l")))
            file:close()
            ngx.say("body excluded: ", entry.response.body == nil)
        }
    }
--- response_body
body excluded: true



=== TEST 8: capture request bodies before a local access-phase rejection
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local path = "file-logger-local-rejection.log"
            os.remove(path)
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/hello",
                plugins = {
                    ["serverless-post-function"] = {
                        phase = "access",
                        functions = {"return function() return 500, 'local rejection' end"}
                    },
                    ["file-logger"] = {
                        path = path,
                        include_req_body = true,
                        include_resp_body = true,
                        _meta = {filter = {{"status", "==", 500}}}
                    }
                }
            })
            assert(code < 300, body)
            local res = assert(require("resty.http").new():request_uri(
                "http://127.0.0.1:1984/hello", {
                    method = "POST",
                    body = "rejected payload"
                }))
            ngx.say(res.status)
            local file = assert(io.open(path, "r"))
            local entry = assert(core.json.decode(file:read("*l")))
            file:close()
            ngx.say(entry.request.body)
            ngx.say(entry.response.body)
        }
    }
--- response_body
500
rejected payload
local rejection
