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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->upstream_server_config) {
        my $upstream = <<_EOC_;
    location = /fp {
        content_by_lua_block {
            ngx.sleep(tonumber(ngx.var.arg_delay) or 0)
            ngx.status = tonumber(ngx.var.arg_code) or 200
            if ngx.status == 204 or ngx.status == 304 then
                return ngx.exit(ngx.status)
            end
            ngx.header["Content-Type"] = "application/json"
            ngx.print('{"from":"upstream"}')
        }
    }
    location = /v1/traces {
        content_by_lua_block {
            ngx.log(ngx.WARN, "otel collector received a span")
        }
    }
_EOC_
        $block->set_value("upstream_server_config", $upstream);
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: invalid filter_phase is rejected
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cjson = require("cjson.safe")
            local filter = {{"status", "==", 200}}
            local cases = {
                {name = "bad enum", plugin = "file-logger", conf = {path = "x.log", _meta = {
                    filter = filter, filter_phase = "balancer"}}},
                {name = "rewrite", plugin = "cors", conf = {_meta = {
                    filter = filter, filter_phase = "rewrite"}}},
                {name = "no filter", plugin = "file-logger", conf = {path = "x.log", _meta = {
                    filter_phase = "log"}}},
                {name = "no such function", plugin = "file-logger", conf = {path = "x.log", _meta = {
                    filter = filter, filter_phase = "header_filter"}}},
                {name = "no later function", plugin = "limit-count", conf = {
                    count = 1, time_window = 60, _meta = {
                    filter = filter, filter_phase = "log"}}},
                {name = "only lua_body_filter", plugin = "ai-aws-content-moderation", conf = {
                    comprehend = {access_key_id = "a", secret_access_key = "b",
                                  region = "us-east-1"}, _meta = {
                    filter = filter, filter_phase = "header_filter"}}},
            }
            for _, case in ipairs(cases) do
                local code, body = t("/apisix/admin/routes/1", ngx.HTTP_PUT, cjson.encode({
                    uri = "/fp",
                    plugins = {[case.plugin] = case.conf},
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}},
                }))
                ngx.say(case.name, ": ", code, " ", cjson.decode(body).error_msg)
            end
        }
    }
--- response_body
bad enum: 400 failed to check the configuration of plugin file-logger err: property "_meta" validation failed: property "filter_phase" validation failed: matches none of the enum values
rewrite: 400 failed to check the configuration of plugin cors err: property "_meta" validation failed: property "filter_phase" validation failed: matches none of the enum values
no filter: 400 failed to check the configuration of plugin file-logger err: property "_meta" validation failed: property "filter" is required when "filter_phase" is set
no such function: 400 invalid _meta.filter_phase of plugin file-logger: it has no header_filter function
no later function: 400 invalid _meta.filter_phase of plugin limit-count: it has no log function
only lua_body_filter: 400 invalid _meta.filter_phase of plugin ai-aws-content-moderation: it has no header_filter function



=== TEST 2: filter_phase is accepted when the plugin has that function, also on stream routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cjson = require("cjson.safe")
            local function route(plugin, conf, filter_phase)
                conf._meta = {filter = {{"arg_a", "==", "1"}}, filter_phase = filter_phase}
                local code, body = t("/apisix/admin/routes/1", ngx.HTTP_PUT, cjson.encode({
                    uri = "/fp",
                    plugins = {[plugin] = conf},
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}},
                }))
                ngx.say(plugin, " ", filter_phase, ": ", code < 300 and "ok" or body)
            end

            route("limit-count", {count = 1, time_window = 60}, "access")
            route("file-logger", {path = "x.log"}, "body_filter")
            route("ai-aws-content-moderation", {comprehend = {access_key_id = "a",
                  secret_access_key = "b", region = "us-east-1"}}, "lua_body_filter")

            local function stream_route(plugin, conf, filter_phase)
                conf._meta = {filter = {{"remote_addr", "==", "127.0.0.1"}},
                              filter_phase = filter_phase}
                local code, body = t("/apisix/admin/stream_routes/1", ngx.HTTP_PUT,
                    cjson.encode({
                        plugins = {[plugin] = conf},
                        upstream = {type = "roundrobin", nodes = {["127.0.0.1:1995"] = 1}},
                    }))
                ngx.say("stream ", plugin, " ", filter_phase, ": ",
                        code < 300 and "ok" or body)
            end

            stream_route("ip-restriction", {blacklist = {"10.0.0.1"}}, "log")
            stream_route("limit-conn", {conn = 1, burst = 0, default_conn_delay = 0.1,
                                        key = "remote_addr"}, "log")

            t("/apisix/admin/stream_routes/1", ngx.HTTP_DELETE)
        }
    }
--- response_body
limit-count access: ok
file-logger body_filter: ok
ai-aws-content-moderation lua_body_filter: ok
stream ip-restriction log: {"error_msg":"invalid _meta.filter_phase of plugin ip-restriction: it has no log function"}

stream limit-conn log: ok



=== TEST 3: functions before the named phase run, false there gates later ones, skipping it decides nothing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")

            local function run(filter_phase, sequence)
                local ran = {}
                local fake = {name = "fake"}
                for _, phase in ipairs({"rewrite", "access", "preread", "before_proxy",
                                        "lua_body_filter", "header_filter", "body_filter",
                                        "delayed_body_filter", "ws_handshake",
                                        "ws_client_frame", "ws_upstream_frame", "ws_close",
                                        "log"}) do
                    fake[phase] = function()
                        ran[#ran + 1] = phase
                    end
                end

                local conf = {_meta = {filter = {{"arg_nope", "==", "1"}},
                                       filter_phase = filter_phase}}
                local api_ctx = {conf_type = "route", conf_id = "1", conf_version = 1,
                                 var = {}, ngx_ctx = ngx.ctx}
                api_ctx.plugins = {fake, conf}
                for _, phase in ipairs(sequence) do
                    if phase == "lua_body_filter" then
                        plugin.lua_response_filter(api_ctx, {}, "", true)
                    else
                        plugin.run_plugin(phase, nil, api_ctx)
                    end
                end
                ngx.say(filter_phase, ":", #ran > 0 and " " or "", table.concat(ran, " "))
            end

            local http = {"rewrite", "rewrite_in_consumer", "access", "before_proxy",
                          "header_filter", "body_filter", "delayed_body_filter", "log"}
            for _, filter_phase in ipairs({"access", "before_proxy", "lua_body_filter",
                                           "header_filter", "body_filter", "log"}) do
                run(filter_phase, http)
            end

            ngx.say("no body_filter")
            run("body_filter", {"rewrite", "access", "before_proxy", "header_filter", "log"})

            ngx.say("stream")
            local stream = {"preread", "before_proxy", "log"}
            for _, filter_phase in ipairs({"access", "before_proxy", "log"}) do
                run(filter_phase, stream)
            end

            ngx.say("streaming, interleaved with the response phases")
            local ai = {"access", "before_proxy", "lua_body_filter", "header_filter",
                        "body_filter", "lua_body_filter", "body_filter", "log"}
            for _, filter_phase in ipairs({"before_proxy", "lua_body_filter", "header_filter",
                                           "log"}) do
                run(filter_phase, ai)
            end

            ngx.say("websocket")
            local ws = {"before_proxy", "ws_handshake", "ws_client_frame", "ws_upstream_frame",
                        "ws_close", "log"}
            for _, filter_phase in ipairs({"before_proxy", "header_filter", "log"}) do
                run(filter_phase, ws)
            end
        }
    }
--- response_body
access: rewrite rewrite
before_proxy: rewrite rewrite access
lua_body_filter: rewrite rewrite access before_proxy header_filter body_filter delayed_body_filter log
header_filter: rewrite rewrite access before_proxy
body_filter: rewrite rewrite access before_proxy header_filter
log: rewrite rewrite access before_proxy header_filter body_filter delayed_body_filter
no body_filter
body_filter: rewrite access before_proxy header_filter log
stream
access: preread before_proxy log
before_proxy: preread
log: preread before_proxy
streaming, interleaved with the response phases
before_proxy: access
lua_body_filter: access before_proxy
header_filter: access before_proxy lua_body_filter
log: access before_proxy lua_body_filter header_filter body_filter lua_body_filter body_filter
websocket
before_proxy:
header_filter: before_proxy ws_handshake ws_client_frame ws_upstream_frame ws_close log
log: before_proxy ws_handshake ws_client_frame ws_upstream_frame ws_close



=== TEST 4: logger with filter_phase=log logs the real status and response body
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["fault-injection"] = {abort = {http_status = 404, body = "gateway-404\n",
                                                vars = {{{"arg_gw", "==", "1"}}}}},
                ["file-logger"] = {
                    path = "filter-phase-log.log",
                    include_resp_body = true,
                    _meta = {
                        filter = {"OR", {"status", "~=", 404}, {"upstream_status", "==", 404}},
                        filter_phase = "log",
                    },
                },
            })

            ngx.say(h.req("?code=200").status)
            ngx.say(h.req("?code=404").status)
            ngx.say(h.req("?gw=1").status)
            h.say_log_entries("filter-phase-log.log")
        }
    }
--- response_body
200
404
404
200 {"from":"upstream"}
404 {"from":"upstream"}
end of log



=== TEST 5: logger with filter_phase=body_filter logs the same and does not buffer excluded requests
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["fault-injection"] = {abort = {http_status = 404, body = "gateway-404\n",
                                                vars = {{{"arg_gw", "==", "1"}}}}},
                ["file-logger"] = {
                    path = "filter-phase-body.log",
                    include_resp_body = true,
                    _meta = {
                        filter = {"OR", {"status", "~=", 404}, {"upstream_status", "==", 404}},
                        filter_phase = "body_filter",
                    },
                },
                ["serverless-post-function"] = {
                    phase = "log",
                    functions = {[[return function(conf, ctx)
                        ngx.log(ngx.WARN, "probe ", ctx.var.arg_tag, " buffered: ",
                                ctx.resp_body and #ctx.resp_body or "nothing")
                    end]]},
                },
            })

            ngx.say(h.req("?code=200&tag=included-200").status)
            ngx.say(h.req("?code=404&tag=included-404").status)
            ngx.say(h.req("?gw=1&tag=excluded").status)
            h.say_log_entries("filter-phase-body.log")
        }
    }
--- response_body
200
404
404
200 {"from":"upstream"}
404 {"from":"upstream"}
end of log
--- grep_error_log eval
qr/probe \S+ buffered: \w+/
--- grep_error_log_out
probe included-200 buffered: 19
probe included-404 buffered: 19
probe excluded buffered: nothing



=== TEST 6: a logger on filter_phase=body_filter decides nothing when body_filter does not run
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["file-logger"] = {
                    path = "filter-phase-head.log",
                    _meta = {
                        filter = {{"status", ">=", 500}},
                        filter_phase = "body_filter",
                    },
                },
            })

            ngx.say("GET ", h.req("?code=200").status)
            ngx.say("HEAD ", h.req("?code=200", "HEAD").status)
            ngx.say("GET ", h.req("?code=204").status)
            ngx.say("GET ", h.req("?code=304").status)
            ngx.say("GET ", h.req("?code=500").status)

            local sock = ngx.socket.tcp()
            sock:connect("127.0.0.1", ngx.var.server_port)
            sock:send("GET /fp?delay=0.5 HTTP/1.1\r\nHost: localhost\r\n\r\n")
            ngx.sleep(0.05)
            sock:close()
            ngx.sleep(1)

            h.say_log_entries("filter-phase-head.log")
        }
    }
--- response_body
GET 200
HEAD 200
GET 204
GET 304
GET 500
200 nil
500 nil
499 nil
end of log



=== TEST 7: a logger on filter_phase=access decides nothing when a rewrite plugin responds first
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cjson = require("cjson.safe")
            local code, body = t("/apisix/admin/consumers", ngx.HTTP_PUT, cjson.encode({
                username = "filter_phase_rejected",
                plugins = {["key-auth"] = {key = "filter-phase-rejected"}},
            }))
            if code >= 300 then
                ngx.say(body)
                return
            end

            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["key-auth"] = {},
                ["file-logger"] = {
                    path = "filter-phase-401.log",
                    _meta = {filter = {{"arg_nope", "==", "1"}}, filter_phase = "access"},
                },
            })

            ngx.say(h.req("?code=200").status)
            ngx.say(h.req("?code=200", "GET", {apikey = "filter-phase-rejected"}).status)
            h.say_log_entries("filter-phase-401.log")
        }
    }
--- response_body
401
200
401 nil
end of log



=== TEST 8: exact filtering on filter_phase=log buffers excluded bodies unless the expr repeats it
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            local probe = {
                phase = "log",
                functions = {[[return function(conf, ctx)
                    ngx.log(ngx.WARN, "probe ", ctx.var.arg_tag, " buffered: ",
                            ctx.resp_body and #ctx.resp_body or "nothing")
                end]]},
            }
            local filter = {{"status", ">=", 500}}

            h.set_route({
                ["file-logger"] = {
                    path = "filter-phase-5xx.log",
                    include_resp_body = true,
                    _meta = {filter = filter, filter_phase = "log"},
                },
                ["serverless-post-function"] = probe,
            })
            ngx.say(h.req("?code=200&tag=no-expr-200").status)
            ngx.say(h.req("?code=500&tag=no-expr-500").status)

            h.set_route({
                ["file-logger"] = {
                    path = "filter-phase-5xx.log",
                    include_resp_body = true,
                    include_resp_body_expr = filter,
                    _meta = {filter = filter, filter_phase = "log"},
                },
                ["serverless-post-function"] = probe,
            })
            ngx.say(h.req("?code=200&tag=expr-200").status)
            ngx.say(h.req("?code=500&tag=expr-500").status)

            h.say_log_entries("filter-phase-5xx.log")
        }
    }
--- response_body
200
500
200
500
500 {"from":"upstream"}
500 {"from":"upstream"}
end of log
--- grep_error_log eval
qr/probe \S+ buffered: \w+/
--- grep_error_log_out
probe no-expr-200 buffered: 19
probe no-expr-500 buffered: 19
probe expr-200 buffered: nothing
probe expr-500 buffered: 19



=== TEST 9: body-transformer with filter_phase=header_filter transforms 200 and leaves 404
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["body-transformer"] = {
                    response = {input_format = "json",
                                template = ngx.encode_base64('{"transformed":true}')},
                    _meta = {filter = {{"status", "==", 200}}, filter_phase = "header_filter"},
                },
            })

            local res = h.req("?code=200")
            ngx.say(res.status, " ", res.body)
            res = h.req("?code=404")
            ngx.say(res.status, " ", res.body)
        }
    }
--- response_body
200 {"transformed":true}
404 {"from":"upstream"}



=== TEST 10: filter_phase unset, response-rewrite turning 404 into 200 changes status and body
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["response-rewrite"] = {
                    status_code = 200,
                    body = "rewritten\n",
                    _meta = {filter = {{"status", "==", 404}}},
                },
            })

            local res = h.req("?code=404")
            ngx.say(res.status, " ", res.body)
            res = h.req("?code=500")
            ngx.say(res.status, " ", res.body)
        }
    }
--- response_body
200 rewritten

500 {"from":"upstream"}



=== TEST 11: filter_phase unset, limit-conn releases the connection on a response the filter names
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["limit-conn"] = {
                    conn = 1, burst = 0, default_conn_delay = 0.1, key = "remote_addr",
                    _meta = {filter = {{"status", "~=", 500}}},
                },
            })

            for _, code in ipairs({500, 200, 200}) do
                ngx.say(h.req("?code=" .. code).status)
            end
        }
    }
--- response_body
500
200
200



=== TEST 12: a logger filter on status does not poison response-rewrite's vars on status
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["file-logger"] = {
                    path = "filter-phase-poison.log",
                    _meta = {filter = {{"status", "==", 200}}},
                },
                ["response-rewrite"] = {
                    headers = {set = {["X-Rewritten"] = "yes"}},
                    vars = {{"status", "==", 200}},
                },
            })

            local res = h.req("?code=200")
            ngx.say(res.status, " ", tostring(res.headers["X-Rewritten"]))
        }
    }
--- response_body
200 yes



=== TEST 13: response variables read early do not stick
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["serverless-pre-function"] = {
                    phase = "access",
                    functions = {[[return function(conf, ctx)
                        local _ = ctx.var.status, ctx.var.bytes_sent, ctx.var.body_bytes_sent,
                                  ctx.var.request_time
                    end]]},
                },
                ["serverless-post-function"] = {
                    phase = "log",
                    functions = {[[return function(conf, ctx)
                        ngx.log(ngx.WARN, "at log: status=", ctx.var.status,
                                " bytes_sent>0=", tonumber(ctx.var.bytes_sent) > 0,
                                " body_bytes_sent>0=", tonumber(ctx.var.body_bytes_sent) > 0,
                                " request_time>=0.1=", tonumber(ctx.var.request_time) >= 0.1)
                    end]]},
                },
            })

            ngx.say(h.req("?code=201&delay=0.1").status)
        }
    }
--- response_body
201
--- error_log
at log: status=201 bytes_sent>0=true body_bytes_sent>0=true request_time>=0.1=true



=== TEST 14: filter_phase=log can filter on bytes_sent
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["file-logger"] = {
                    path = "filter-phase-bytes.log",
                    _meta = {filter = {{"bytes_sent", ">", 0}}, filter_phase = "log"},
                },
            })

            ngx.say(h.req("?code=200").status)
            h.say_log_entries("filter-phase-bytes.log")
        }
    }
--- response_body
200
200 nil
end of log



=== TEST 15: cors with filter_phase=header_filter keeps the Origin saved by its rewrite
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["cors"] = {
                    _meta = {filter = {{"status", "==", 200}}, filter_phase = "header_filter"},
                },
            })

            for _, code in ipairs({200, 404}) do
                local res = h.req("?code=" .. code, "GET", {Origin = "http://example.com"})
                ngx.say(res.status, " ", tostring(res.headers["Access-Control-Allow-Origin"]))
            end
        }
    }
--- response_body
200 *
404 nil



=== TEST 16: a plugin on the consumer runs its rewrite before the named phase
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cjson = require("cjson.safe")
            local code, body = t("/apisix/admin/consumers", ngx.HTTP_PUT, cjson.encode({
                username = "filter_phase_consumer",
                plugins = {
                    ["key-auth"] = {key = "filter-phase-key"},
                    ["cors"] = {
                        _meta = {filter = {{"status", "==", 200}},
                                 filter_phase = "header_filter"},
                    },
                },
            }))
            if code >= 300 then
                ngx.say(body)
                return
            end

            local h = require("lib.meta_filter_phase")
            h.set_route({["key-auth"] = {}})

            for _, code in ipairs({200, 404}) do
                local res = h.req("?code=" .. code, "GET", {
                    Origin = "http://example.com",
                    apikey = "filter-phase-key",
                })
                ngx.say(res.status, " ", tostring(res.headers["Access-Control-Allow-Origin"]))
            end
        }
    }
--- response_body
200 *
404 nil



=== TEST 17: opentelemetry with filter_phase=log exports only the requests the filter includes
--- extra_yaml_config
plugins:
    - opentelemetry
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/plugin_metadata/opentelemetry", ngx.HTTP_PUT, [[{
                "batch_span_processor": {
                    "max_export_batch_size": 1,
                    "inactive_timeout": 0.5
                },
                "collector": {
                    "address": "127.0.0.1:1980",
                    "request_timeout": 3
                }
            }]])
            if code >= 300 then
                ngx.say(body)
                return
            end
            ngx.sleep(1)

            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["opentelemetry"] = {
                    sampler = {name = "always_on"},
                    _meta = {filter = {{"status", ">=", 500}}, filter_phase = "log"},
                },
            })

            for _, code in ipairs({200, 200, 500}) do
                ngx.say(h.req("?code=" .. code).status)
            end
            ngx.sleep(2)
        }
    }
--- response_body
200
200
500
--- grep_error_log eval
qr/otel collector received a span/
--- grep_error_log_out
otel collector received a span
--- timeout: 10



=== TEST 18: the final upstream status after a retry is matched with a regex
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cjson = require("cjson.safe")
            local code, body = t("/apisix/admin/routes/1", ngx.HTTP_PUT, cjson.encode({
                uri = "/fp",
                plugins = {
                    ["fault-injection"] = {abort = {http_status = 404, body = "gateway-404\n",
                                                    vars = {{{"arg_gw", "==", "1"}}}}},
                    ["file-logger"] = {
                        path = "filter-phase-retry.log",
                        _meta = {
                            filter = {"OR", {"status", "~=", 404},
                                      {"upstream_status", "~~", "404$"}},
                            filter_phase = "body_filter",
                        },
                    },
                    ["serverless-post-function"] = {
                        phase = "log",
                        functions = {[[return function(conf, ctx)
                            ngx.log(ngx.WARN, "upstream_status: ", ctx.var.upstream_status)
                        end]]},
                    },
                },
                upstream = {
                    type = "roundrobin",
                    retries = 1,
                    nodes = {
                        {host = "127.0.0.1", port = 1979, weight = 1, priority = 1},
                        {host = "127.0.0.1", port = 1980, weight = 1, priority = 0},
                    },
                },
            }))
            if code >= 300 then
                ngx.say(body)
                return
            end

            local h = require("lib.meta_filter_phase")
            ngx.say(h.req("?code=404").status)
            ngx.say(h.req("?gw=1").status)
            h.say_log_entries("filter-phase-retry.log")
        }
    }
--- response_body
404
404
404 nil
end of log
--- error_log
upstream_status: 502, 404



=== TEST 19: filter_phase=access on a consumer-merged route decides after the merge
--- upstream_server_config
    location = /fp {
        content_by_lua_block {
            ngx.print("traced: ", ngx.var.http_x_b3_traceid ~= nil)
        }
    }
--- extra_yaml_config
plugins:
    - key-auth
    - zipkin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cjson = require("cjson.safe")
            for _, name in ipairs({"alice", "bob"}) do
                local code, body = t("/apisix/admin/consumers", ngx.HTTP_PUT, cjson.encode({
                    username = "filter_phase_" .. name,
                    plugins = {["key-auth"] = {key = "filter-phase-" .. name}},
                }))
                if code >= 300 then
                    ngx.say(body)
                    return
                end
            end

            local h = require("lib.meta_filter_phase")
            h.set_route({
                ["key-auth"] = {},
                ["zipkin"] = {
                    endpoint = "http://127.0.0.1:1980/mock_zipkin",
                    sample_ratio = 0.00001,
                    _meta = {filter = {{"consumer_name", "==", "filter_phase_alice"}},
                             filter_phase = "access"},
                },
            })

            for _, name in ipairs({"alice", "bob"}) do
                local res = h.req("", "GET", {apikey = "filter-phase-" .. name})
                ngx.say(name, " ", res.status, " ", res.body)
            end
        }
    }
--- response_body
alice 200 traced: true
bob 200 traced: false
