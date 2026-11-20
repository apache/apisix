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

    if (! $block->request) {
        $block->set_value("request", "GET /t");
        if (!$block->response_body) {
            $block->set_value("response_body", "passed\n");
        }
    }

    if (!defined $block->http_config) {
        my $http_config = <<_EOC_;
    server {
        listen 11463;
        location ~ ^/compressed/(.+)\$ {
            content_by_lua_block {
                local gzip = require("apisix.utils.gzip")
                local text = string.rep("hello world\\n", 10000)
                local stored = string.rep("0123456789", 200)
                local bodies = {
                    ["text-gzip"] = {"gzip", gzip.deflate_gzip(text)},
                    ["stored-gzip"] = {"gzip", gzip.deflate_gzip(stored, nil, {level = 0})},
                    ["not-gzip"] = {"gzip", "not a gzip stream"},
                }
                local ok, brotli = pcall(require, "brotli")
                if ok then
                    local numbers = {}
                    for i = 1, 20000 do
                        numbers[i] = i
                    end
                    bodies["text-br"] = {"br", brotli:compress(table.concat(numbers, " "))}
                    bodies["not-br"] = {"br", "not a brotli stream"}
                end

                local case = ngx.var[1]
                if case == "empty" or case == "204" or case == "304" or case == "empty-br" then
                    ngx.status = tonumber(case) or 200
                    ngx.header["Content-Encoding"] = case == "empty-br" and "br" or "gzip"
                    ngx.header["Content-Length"] = 0
                    ngx.send_headers()
                    return
                end

                ngx.header["Content-Encoding"] = bodies[case][1]
                ngx.print(bodies[case][2])
            }
        }
    }
_EOC_
        $block->set_value("http_config", $http_config);
    }
});


run_tests;

__DATA__

=== TEST 1: add plugin with 'include_resp_body' setting
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- delete plugin metadata for response body format
            t('/apisix/admin/plugin_metadata/file-logger', ngx.HTTP_DELETE)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-resp-body.log",
                                "include_resp_body": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 2: verify plugin for file-logger with response
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-with-resp-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-resp-check.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code

            if new_msg.response ~= nil and new_msg.response.body == "hello world\n" then
                ngx.status = code
                ngx.say('contain with target')
            end
        }
    }
--- response_body
contain with target



=== TEST 3: check file-logger 'include_resp_body' with 'expr'
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-resp-expr-body.log",
                                "include_resp_body": true,
                                "include_resp_body_expr": [
                                    [
                                      "arg_foo",
                                      "==",
                                      "bar"
                                    ]
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 4: verify file-logger resp with expression of concern
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello?foo=bar", ngx.HTTP_GET)
            local fd, err = io.open("file-with-resp-expr-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-with-resp-expr-body.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code

            if new_msg.response ~= nil and new_msg.response.body == "hello world\n" then
                ngx.status = code
                ngx.say('contain target body hits with expr')
            end

            --- a new request is logged
            t("/hello?name=pix", ngx.HTTP_GET)
            msg = fd:read("*l")
            local new_msg = core.json.decode(msg)
            if new_msg.response.body == nil then
                ngx.say('skip unconcern body')
            end
        }
    }
--- response_body
contain target body hits with expr
skip unconcern body



=== TEST 5: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "host": "$host",
                        "client_ip": "$remote_addr",
                        "resp_body": "$resp_body"
                    }
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



=== TEST 6: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-resp-body2.log",
                                "include_resp_body": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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
--- response_body
passed



=== TEST 7: verify plugin
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-with-resp-body2.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file.log, error info: ", err)
                return
            end

            msg = fd:read()

            local new_msg = core.json.decode(msg)
            if new_msg.resp_body == 'hello world\n'
            then
                msg = "write file log success"
                ngx.status = code
                ngx.say(msg)
            end
        }
    }
--- response_body
write file log success



=== TEST 8: Add new configuration with match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-match.log",
                                "match": [
                                    [
                                        [ "arg_name","==","jack" ]
                                    ]
                                ],
                                "log_format": {
                                    "request": "$request"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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
--- response_body
passed



=== TEST 9: Request match
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello?name=jack", ngx.HTTP_GET)
            local fd, err = io.open("file-with-match.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-with-match.log, error info: ", err)
                return
            end
            local msg = fd:read()

            local new_msg = core.json.decode(msg)
            if new_msg.request == 'GET /hello?name=jack HTTP/1.1'
                and new_msg.route_id == '1'
            then
                msg = "write file log success"
                ngx.status = code
                ngx.say(msg)
            end

            os.remove("file-with-match.log")
        }
    }
--- response_body
write file log success



=== TEST 10: Request not match
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello?name=tony", ngx.HTTP_GET)
            local fd, err = io.open("file-with-match.log", 'r')
            if not fd then
                local msg = "not write file log"
                ngx.say(msg)
                return
            end
        }
    }
--- response_body
not write file log



=== TEST 11: add plugin with 'include_req_body' setting
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/plugin_metadata/file-logger', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-req-body.log",
                                "include_req_body": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 12: verify plugin for file-logger with request
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_POST, "body-data")
            local fd, err = io.open("file-with-req-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-with-req-body.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code
            if new_msg.request ~= nil and new_msg.request.body == "body-data" then
                ngx.status = code
                ngx.say('contain with target')
            end
        }
    }
--- response_body
contain with target



=== TEST 13: check file-logger 'include_req_body' with 'expr'
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-with-req-expr-body.log",
                                "include_req_body": true,
                                "include_req_body_expr": [
                                    [
                                      "arg_log_body",
                                      "==",
                                      "yes"
                                    ]
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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



=== TEST 14: verify file-logger req with expression of concern
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello?log_body=yes",
                ngx.HTTP_POST,
                [[{"foo": "bar"}]]
                )
            local fd, err = io.open("file-with-req-expr-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-with-req-expr-body.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code
            if new_msg.request ~= nil and new_msg.request.body ~= nil then
                ngx.status = code
                ngx.say('contain target body hits with expr')
            end

            --- a new request is logged
            t("/hello?log_body=no", ngx.HTTP_POST, [[{"foo": "b"}]])
            msg = fd:read("*l")
            local new_msg = core.json.decode(msg)
            if new_msg.request.body == nil then
                ngx.say('skip unconcern body')
            end
        }
    }
--- response_body
contain target body hits with expr
skip unconcern body



=== TEST 15: collecting response body gzipped by APISIX
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "file-logger": {
                            "path": "file-with-uncompressed-resp-body.log",
                            "include_resp_body": true
                        },
                        "gzip": {
                             "min_length": 10
                     }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code = t("/hello", ngx.HTTP_GET, nil, nil, {['Accept-Encoding']='gzip'})
            local fd, err = io.open("file-with-uncompressed-resp-body.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-with-uncompressed-resp-body.log, error info: ", err)
                return
            end

            -- note only for first line
            msg = fd:read()

            local new_msg = core.json.decode(msg)
            ngx.status = code
            if new_msg.response ~= nil and new_msg.response.body == "hello world\n" then
                ngx.say('contain with target')
            end
        }
    }
--- no_error_log
try decode compressed data err: inflate gzip err: INFLATE: data error
--- response_body
contain with target



=== TEST 16: set routes to upstreams sending compressed bodies
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local gzip = require("apisix.utils.gzip")
            local stored = string.rep("0123456789", 200)
            local exact = #gzip.deflate_gzip(stored, nil, {level = 0})

            local routes = {
                {uri = "/compressed/empty"},
                {uri = "/compressed/204"},
                {uri = "/compressed/304"},
                {uri = "/compressed/text-gzip", max = 100},
                {uri = "/compressed/stored-gzip", max = 100},
                {uri = "/compressed/stored-gzip-exact", upstream = "/compressed/stored-gzip",
                 max = exact},
                {uri = "/compressed/not-gzip"},
                {uri = "/compressed/text-gzip-under", upstream = "/compressed/text-gzip",
                 max = 10000},
                {uri = "/compressed/empty-br"},
                {uri = "/compressed/text-br", max = 5000},
                {uri = "/compressed/text-br-under", upstream = "/compressed/text-br",
                 max = 50000},
                {uri = "/compressed/not-br"},
            }
            for i, route in ipairs(routes) do
                local code, body = t("/apisix/admin/routes/" .. i, ngx.HTTP_PUT,
                    core.json.encode({
                        uri = route.uri,
                        plugins = {
                            ["file-logger"] = {
                                path = "file-logger-compressed.log",
                                include_resp_body = true,
                                max_resp_body_bytes = route.max,
                            },
                            ["proxy-rewrite"] = {
                                uri = route.upstream or route.uri,
                            },
                        },
                        upstream = {
                            nodes = {["127.0.0.1:11463"] = 1},
                            type = "roundrobin",
                        },
                    })
                )
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }



=== TEST 17: empty bodies labelled gzip are logged as empty
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            for _, case in ipairs({"empty", "204", "304"}) do
                local code = t("/compressed/" .. case, ngx.HTTP_GET)
                local fd = assert(io.open("file-logger-compressed.log"))
                local last
                for line in fd:lines() do
                    last = line
                end
                fd:close()
                local resp = core.json.decode(last).response
                ngx.say(code, " ", resp.headers["content-encoding"], " [", resp.body, "]")
            end
        }
    }
--- response_body
200 gzip []
204 gzip []
304 gzip []
--- no_error_log
try decode compressed data err



=== TEST 18: a gzip body cut at the limit is logged as the plaintext decoded from it
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local plaintexts = {
                ["text-gzip"] = string.rep("hello world\n", 10000),
                ["stored-gzip"] = string.rep("0123456789", 200),
            }
            for _, case in ipairs({"text-gzip", "stored-gzip"}) do
                t("/compressed/" .. case, ngx.HTTP_GET)
                local fd = assert(io.open("file-logger-compressed.log"))
                local last
                for line in fd:lines() do
                    last = line
                end
                fd:close()
                local body = core.json.decode(last).response.body
                ngx.say(case, " ", #body, " ", body == string.sub(plaintexts[case], 1, #body))
            end
        }
    }
--- response_body
text-gzip 100 true
stored-gzip 85 true
--- no_error_log
try decode compressed data err



=== TEST 19: a complete gzip body exactly at the limit is decoded in full
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            t("/compressed/stored-gzip-exact", ngx.HTTP_GET)
            local fd = assert(io.open("file-logger-compressed.log"))
            local last
            for line in fd:lines() do
                last = line
            end
            fd:close()
            local body = core.json.decode(last).response.body
            ngx.say(body == string.rep("0123456789", 200))
        }
    }
--- response_body
true
--- no_error_log
try decode compressed data err



=== TEST 20: a body below the limit that fails to decode is logged as received
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            t("/compressed/not-gzip", ngx.HTTP_GET)
            local fd = assert(io.open("file-logger-compressed.log"))
            local last
            for line in fd:lines() do
                last = line
            end
            fd:close()
            ngx.say(core.json.decode(last).response.body)
        }
    }
--- response_body
not a gzip stream
--- error_log
try decode compressed data err: inflate gzip err



=== TEST 21: the plaintext of a gzip body under the limit is held to the limit
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local plain = string.rep("hello world\n", 10000)
            t("/compressed/text-gzip-under", ngx.HTTP_GET)
            local fd = assert(io.open("file-logger-compressed.log"))
            local last
            for line in fd:lines() do
                last = line
            end
            fd:close()
            local body = core.json.decode(last).response.body
            ngx.say(#body, " ", body == string.sub(plain, 1, #body))
        }
    }
--- response_body
10000 true
--- no_error_log
try decode compressed data err



=== TEST 22: br bodies that are empty, cut at the limit or decoding past it are logged without error
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local numbers = {}
            for i = 1, 20000 do
                numbers[i] = i
            end
            local plain = table.concat(numbers, " ")
            for _, case in ipairs({"empty-br", "text-br", "text-br-under"}) do
                t("/compressed/" .. case, ngx.HTTP_GET)
                local fd = assert(io.open("file-logger-compressed.log"))
                local last
                for line in fd:lines() do
                    last = line
                end
                fd:close()
                local body = core.json.decode(last).response.body
                ngx.say(case, " ", #body, " ", body == string.sub(plain, 1, #body))
            end
        }
    }
--- response_body
empty-br 0 true
text-br 5000 true
text-br-under 50000 true
--- no_error_log
try decode compressed data err



=== TEST 23: a br body below the limit that fails to decode is logged as received
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            t("/compressed/not-br", ngx.HTTP_GET)
            local fd = assert(io.open("file-logger-compressed.log"))
            local last
            for line in fd:lines() do
                last = line
            end
            fd:close()
            ngx.say(core.json.decode(last).response.body)
        }
    }
--- response_body
not a brotli stream
--- error_log
try decode compressed data err: brotli decode err
