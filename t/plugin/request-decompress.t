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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: schema defaults
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-decompress")
            local conf = {}
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("max_req_body_size: ", conf.max_req_body_size)
            ngx.say("forward_compressed: ", conf.forward_compressed)
        }
    }
--- response_body
max_req_body_size: 1048576
forward_compressed: false



=== TEST 2: max_req_body_size must be positive
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-decompress")
            local ok, err = plugin.check_schema({max_req_body_size = 0})
            ngx.say(ok, " ", err)
        }
    }
--- response_body
false property "max_req_body_size" validation failed: expected 0 to be at least 1



=== TEST 3: route with the plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/echo",
                    plugins = {
                        ["request-decompress"] = {}
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    }
                })
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: gzip body is forwarded uncompressed
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip([[{"name":"doggie"}]])

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body: ", res.body)
        }
    }
--- response_body
status: 200
content-encoding: none
upstream body: {"name":"doggie"}



=== TEST 5: deflate body is forwarded uncompressed
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            -- windowBits 15 emits a zlib stream, which is the deflate coding
            local body = gzip.deflate_gzip([[{"name":"doggie"}]], nil, {windowBits = 15})

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "deflate"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body: ", res.body)
        }
    }
--- response_body
status: 200
content-encoding: none
upstream body: {"name":"doggie"}



=== TEST 6: chained codings are inflated in reverse order
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip(gzip.deflate_gzip([[{"name":"doggie"}]]))

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip, gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body: ", res.body)
        }
    }
--- response_body
status: 200
content-encoding: none
upstream body: {"name":"doggie"}



=== TEST 7: identity coding leaves the body alone
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = [[{"name":"doggie"}]],
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "identity"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body: ", res.body)
        }
    }
--- response_body
status: 200
content-encoding: none
upstream body: {"name":"doggie"}



=== TEST 8: request without Content-Encoding is untouched
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = [[{"name":"doggie"}]],
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("upstream body: ", res.body)
        }
    }
--- response_body
status: 200
upstream body: {"name":"doggie"}



=== TEST 9: Content-Length is rewritten to the decompressed length
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local code = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/print_request_received",
                    plugins = {
                        ["request-decompress"] = {}
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    }
                })
            )
            if code >= 300 then
                ngx.say("route creation failed: ", code)
                return
            end

            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:1984/print_request_received", {
                method = "POST",
                body = gzip.deflate_gzip([[{"name":"doggie"}]]),
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            for line in res.body:gmatch("[^\n]+") do
                if line:find("^content%-length") or line:find("^content%-encoding") then
                    ngx.say(line)
                end
            end

            t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
        }
    }
--- response_body
content-length: 17



=== TEST 10: corrupt stream is rejected
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = "not a gzip stream at all",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.print(res.body)
        }
    }
--- response_body
status: 400
{"message":"failed to decompress request body"}
--- error_log
failed reading request body, err: inflate gzip err



=== TEST 11: unsupported coding is rejected
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = [[{"name":"doggie"}]],
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "br"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("accept-encoding: ", res.headers["Accept-Encoding"] or "none")
            ngx.print(res.body)
        }
    }
--- response_body
status: 415
accept-encoding: gzip, deflate
{"message":"unsupported content encoding: br"}
--- error_log
failed reading request body, err: unsupported content encoding: br



=== TEST 12: route with a small body size limit
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/echo",
                    plugins = {
                        ["request-decompress"] = {
                            max_req_body_size = 64
                        }
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    }
                })
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: body inflating over max_req_body_size is rejected
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip(string.rep("d", 2048))

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.print(res.body)
        }
    }
--- response_body
status: 413
{"message":"request body is too large"}
--- error_log
inflated data is greater than the maximum size 64 allowed



=== TEST 14: route stacking the plugin with oas-validator
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local spec = core.json.encode({
                openapi = "3.0.2",
                info = {title = "test", version = "1.0"},
                paths = {
                    ["/echo"] = {
                        post = {
                            requestBody = {
                                required = true,
                                content = {
                                    ["application/json"] = {
                                        schema = {
                                            type = "object",
                                            required = {"name"},
                                            properties = {
                                                name = {type = "string"}
                                            }
                                        }
                                    }
                                }
                            },
                            responses = {["200"] = {description = "ok"}}
                        }
                    }
                }
            })

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/echo",
                    plugins = {
                        ["request-decompress"] = {},
                        ["oas-validator"] = {spec = spec}
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    }
                })
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: oas-validator validates the decompressed body
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip([[{"name":"doggie"}]])

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("upstream body: ", res.body)
        }
    }
--- response_body
status: 200
upstream body: {"name":"doggie"}



=== TEST 16: a gzip body failing the spec is rejected by oas-validator
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip([[{"lol":"watdis?"}]])

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.print(res.body)
        }
    }
--- response_body
status: 400
{"message":"failed to validate request. "}
--- error_log
error occurred while validating request



=== TEST 17: Content-Encoding on a request with no body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/echo",
                    plugins = {
                        ["request-decompress"] = {}
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    }
                })
            )
            if code >= 300 then
                ngx.say("route creation failed: ", code)
                return
            end

            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "GET",
                headers = {
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
        }
    }
--- response_body
status: 200
content-encoding: none



=== TEST 18: route forwarding a compressed body, with oas-validator
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local spec = core.json.encode({
                openapi = "3.0.2",
                info = {title = "test", version = "1.0"},
                paths = {
                    ["/echo"] = {
                        post = {
                            requestBody = {
                                required = true,
                                content = {
                                    ["application/json"] = {
                                        schema = {
                                            type = "object",
                                            required = {"name"},
                                            properties = {
                                                name = {type = "string"}
                                            }
                                        }
                                    }
                                }
                            },
                            responses = {["200"] = {description = "ok"}}
                        }
                    }
                }
            })

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/echo",
                    plugins = {
                        ["request-decompress"] = {
                            forward_compressed = true
                        },
                        ["oas-validator"] = {spec = spec}
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    }
                })
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 19: the upstream receives the bytes as they arrived
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip([[{"name":"doggie"}]])

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body unchanged: ", res.body == body)
        }
    }
--- response_body
status: 200
content-encoding: gzip
upstream body unchanged: true



=== TEST 20: the decompressed body is still validated
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip([[{"lol":"watdis?"}]])

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.print(res.body)
        }
    }
--- response_body
status: 400
{"message":"failed to validate request. "}
--- error_log
error occurred while validating request



=== TEST 21: deflate round-trips
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip([[{"name":"doggie"}]], nil, {windowBits = 15})

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "deflate"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body unchanged: ", res.body == body)
        }
    }
--- response_body
status: 200
content-encoding: deflate
upstream body unchanged: true



=== TEST 22: chained codings round-trip
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip(gzip.deflate_gzip([[{"name":"doggie"}]]))

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip, gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body unchanged: ", res.body == body)
        }
    }
--- response_body
status: 200
content-encoding: gzip, gzip
upstream body unchanged: true



=== TEST 23: an uncompressed request on the same route is untouched
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = [[{"name":"doggie"}]],
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body: ", res.body)
        }
    }
--- response_body
status: 200
content-encoding: none
upstream body: {"name":"doggie"}



=== TEST 24: route forwarding a compressed body, with body-transformer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/echo",
                    plugins = {
                        ["request-decompress"] = {
                            forward_compressed = true
                        },
                        ["body-transformer"] = {
                            request = {
                                template = [[{"foo":"{{name .. " world"}}","bar":{{age+10}}}]]
                            }
                        }
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    }
                })
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 25: a rewritten body is compressed again before it is forwarded
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")
            local body = gzip.deflate_gzip([[{"name":"hello","age":20}]])

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = body,
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body unchanged: ", res.body == body)
            ngx.say("upstream body inflates to: ", gzip.inflate_gzip(res.body))
        }
    }
--- response_body
status: 200
content-encoding: gzip
upstream body unchanged: false
upstream body inflates to: {"foo":"hello world","bar":30}



=== TEST 26: route whose body another plugin moves to a file
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            local func = [[return function(conf, ctx)
                local path = ngx.config.prefix() .. "logs/request-decompress-body.txt"
                local f = assert(io.open(path, "w"))
                f:write('{"name":"from-file"}')
                f:close()
                ngx.req.set_body_file(path)
            end]]

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/echo",
                    plugins = {
                        ["request-decompress"] = {
                            forward_compressed = true
                        },
                        ["serverless-pre-function"] = {
                            phase = "access",
                            functions = {func}
                        }
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    }
                })
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 27: a body held in a file is compressed from the file
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local gzip = require("apisix.utils.gzip")

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = gzip.deflate_gzip([[{"name":"doggie"}]]),
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Encoding"] = "gzip"
                }
            })
            if not res then
                ngx.say(err)
                return
            end

            ngx.say("status: ", res.status)
            ngx.say("content-encoding: ", res.headers["Content-Encoding"] or "none")
            ngx.say("upstream body inflates to: ", gzip.inflate_gzip(res.body))
        }
    }
--- response_body
status: 200
content-encoding: gzip
upstream body inflates to: {"name":"from-file"}
