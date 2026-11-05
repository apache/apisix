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
    $block->set_value("request", "GET /t") unless $block->request;
    $block->set_value("no_error_log", "[error]\n[alert]")
        unless $block->no_error_log || $block->error_log;
});

run_tests;

__DATA__

=== TEST 1: response-rewrite shares its header and body filter decision
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                },
                plugins = {
                    ["response-rewrite"] = {
                        _meta = {filter = {{"status", "==", 200}}},
                        status_code = 403,
                        body = "rewritten body"
                    }
                }
            })
            assert(code < 300, body)
            local res = assert(require("resty.http").new():request_uri(
                "http://127.0.0.1:1984/hello"))
            ngx.say(res.status)
            ngx.say(res.body)
        }
    }
--- response_body
403
rewritten body



=== TEST 2: a false response-rewrite decision stays false in body_filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                },
                plugins = {
                    ["response-rewrite"] = {
                        _meta = {filter = {{"status", "==", 403}}},
                        status_code = 403,
                        body = "rewritten body"
                    }
                }
            })
            assert(code < 300, body)
            local res = assert(require("resty.http").new():request_uri(
                "http://127.0.0.1:1984/hello"))
            ngx.say(res.status)
            ngx.print(res.body)
        }
    }
--- response_body
200
hello world



=== TEST 3: limit-conn releases a slot even if the response no longer matches
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/specific_status",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                },
                plugins = {
                    ["limit-conn"] = {
                        _meta = {filter = {{"status", "~=", 500}}},
                        conn = 1,
                        burst = 0,
                        default_conn_delay = 0.1,
                        key = "http_x_lifecycle_key",
                        key_type = "var"
                    }
                }
            })
            assert(code < 300, body)
            local http = require("resty.http")
            for _, status in ipairs({500, 200, 200}) do
                local res = assert(http.new():request_uri(
                    "http://127.0.0.1:1984/specific_status", {
                        headers = {
                            ["x-test-upstream-status"] = tostring(status),
                            ["x-lifecycle-key"] = "meta-filter-release"
                        }
                    }))
                ngx.say(res.status)
            end
        }
    }
--- response_body
500
200
200



=== TEST 4: logger access prepares data without caching a response decision
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")
            local function record(_, ctx)
                ctx.calls = ctx.calls + 1
            end
            local logger = {
                name = "test-logger",
                type = "logger",
                access = record,
                body_filter = record,
                log = record
            }
            local conf = {_meta = {filter = {{"probe", "==", "allow"}}}}
            local function context()
                return {
                    conf_type = "route",
                    conf_id = "logger-lifecycle",
                    conf_version = 1,
                    ngx_ctx = ngx.ctx,
                    var = {probe = "deny"},
                    calls = 0
                }
            end
            local ctx = context()
            local plugins = {logger, conf}
            plugin.run_plugin("access", plugins, ctx)
            ngx.say("preparation: ", ctx.calls)
            ctx.var.probe = "allow"
            plugin.run_plugin("body_filter", plugins, ctx)
            ctx.var.probe = "deny"
            plugin.run_plugin("body_filter", plugins, ctx)
            plugin.run_plugin("log", plugins, ctx)
            ngx.say("matched: ", ctx.calls)

            ctx = context()
            plugin.run_plugin("access", plugins, ctx)
            plugin.run_plugin("body_filter", plugins, ctx)
            ctx.var.probe = "allow"
            plugin.run_plugin("body_filter", plugins, ctx)
            plugin.run_plugin("log", plugins, ctx)
            ngx.say("unmatched: ", ctx.calls)

            logger.type = nil
            ctx = context()
            plugin.run_plugin("access", plugins, ctx)
            ctx.var.probe = "allow"
            plugin.run_plugin("log", plugins, ctx)
            ngx.say("ordinary plugin: ", ctx.calls)
        }
    }
--- response_body
preparation: 1
matched: 4
unmatched: 1
ordinary plugin: 0



=== TEST 5: body-capturing loggers opt in to deferred access filtering
--- config
    location /t {
        content_by_lua_block {
            local loggers = {
                "clickhouse-logger", "elasticsearch-logger", "file-logger",
                "http-logger", "kafka-logger", "loggly", "loki-logger",
                "rocketmq-logger", "skywalking-logger", "sls-logger", "syslog",
                "tcp-logger", "tencent-cloud-cls", "udp-logger"
            }
            for _, name in ipairs(loggers) do
                local logger = require("apisix.plugins." .. name)
                assert(logger.type == "logger", name)
                assert(logger.access and logger.body_filter and logger.log, name)
            end
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 6: Elasticsearch discovery runs only for emitted batches
--- upstream_server_config
    location = /es-version {
        content_by_lua_block {
            local dict = ngx.shared["plugin-limit-conn"]
            dict:incr("meta-filter-es-reads", 1, 0)
            ngx.say('{"version":{"number":"', dict:get("meta-filter-es-version"), '.0.0"}}')
        }
    }
    location = /es-version/_bulk {
        content_by_lua_block {
            ngx.req.read_body()
            ngx.shared["plugin-limit-conn"]:set("meta-filter-es-bulk", ngx.req.get_body_data())
            ngx.say("{}")
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local dict = ngx.shared["plugin-limit-conn"]
            for _, version in ipairs({"5", "6", "8"}) do
                dict:set("meta-filter-es-version", version)
                dict:delete("meta-filter-es-reads")
                dict:delete("meta-filter-es-bulk")
                local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                    uri = "/specific_status",
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:1980"] = 1}
                    },
                    plugins = {
                        ["elasticsearch-logger"] = {
                            endpoint_addr = "http://127.0.0.1:1980/es-version",
                            field = {index = "filtered-" .. version},
                            batch_max_size = 1,
                            _meta = {filter = {{"status", "==", 201}}}
                        }
                    }
                })
                assert(code < 300, body)
                local http = require("resty.http")
                local res = assert(http.new():request_uri(
                    "http://127.0.0.1:1984/specific_status", {
                        headers = {["x-test-upstream-status"] = "200"}
                    }))
                assert(res.status == 200, res.body)
                ngx.say("excluded discovery: ", dict:get("meta-filter-es-reads") or 0)

                res = assert(http.new():request_uri(
                    "http://127.0.0.1:1984/specific_status", {
                        headers = {["x-test-upstream-status"] = "201"}
                    }))
                assert(res.status == 201, res.body)
                local bulk
                for _ = 1, 100 do
                    bulk = dict:get("meta-filter-es-bulk")
                    if bulk then
                        break
                    end
                    ngx.sleep(0.01)
                end
                assert(bulk, "missing Elasticsearch batch")
                local action, entry = bulk:match("([^\n]+)\n([^\n]+)\n")
                action = assert(core.json.decode(action))
                entry = assert(core.json.decode(entry))
                ngx.say("index: ", action.index._index)
                ngx.say("type: ", action.index._type or "none")
                ngx.say("status: ", entry.response.status)
                ngx.say("discovery: ", dict:get("meta-filter-es-reads"))
            end
        }
    }
--- response_body
excluded discovery: 0
index: filtered-5
type: _doc
status: 201
discovery: 1
excluded discovery: 0
index: filtered-6
type: _doc
status: 201
discovery: 1
excluded discovery: 0
index: filtered-8
type: none
status: 201
discovery: 1



=== TEST 7: a discovery failure retries the captured Elasticsearch entry
--- upstream_server_config
    location = /es-retry {
        content_by_lua_block {
            local dict = ngx.shared["plugin-limit-conn"]
            local count = dict:incr("meta-filter-es-retry-reads", 1, 0)
            if count == 1 then
                return ngx.exit(503)
            end
            ngx.say('{"version":{"number":"6.0.0"}}')
        }
    }
    location = /es-retry/_bulk {
        content_by_lua_block {
            ngx.req.read_body()
            local dict = ngx.shared["plugin-limit-conn"]
            dict:set("meta-filter-es-retry-bulk", ngx.req.get_body_data())
            dict:set("meta-filter-es-retry-discovered", dict:get("meta-filter-es-retry-reads"))
            ngx.say("{}")
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local dict = ngx.shared["plugin-limit-conn"]
            dict:delete("meta-filter-es-retry-reads")
            dict:delete("meta-filter-es-retry-bulk")
            dict:delete("meta-filter-es-retry-discovered")
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                },
                plugins = {
                    ["elasticsearch-logger"] = {
                        endpoint_addr = "http://127.0.0.1:1980/es-retry",
                        field = {index = "retry-captured-entry"},
                        batch_max_size = 1,
                        max_retry_count = 1,
                        retry_delay = 0,
                        include_req_body = true,
                        _meta = {filter = {{"status", "==", 200}}}
                    }
                }
            })
            assert(code < 300, body)
            local res = assert(require("resty.http").new():request_uri(
                "http://127.0.0.1:1984/hello", {
                    method = "POST",
                    body = "retained payload"
                }))
            assert(res.status == 200, res.body)
            local bulk
            for _ = 1, 100 do
                bulk = dict:get("meta-filter-es-retry-bulk")
                if bulk then
                    break
                end
                ngx.sleep(0.01)
            end
            assert(bulk, "missing retried Elasticsearch batch")
            local action, entry = bulk:match("([^\n]+)\n([^\n]+)\n")
            action = assert(core.json.decode(action))
            entry = assert(core.json.decode(entry))
            ngx.say("discovery before bulk: ", dict:get("meta-filter-es-retry-discovered"))
            ngx.say("index: ", action.index._index)
            ngx.say("type: ", action.index._type)
            ngx.say("body: ", entry.request.body)
        }
    }
--- response_body
discovery before bulk: 2
index: retry-captured-entry
type: _doc
body: retained payload
--- error_log
failed to get Elasticsearch version: server returned status: 503
--- no_error_log
[alert]



=== TEST 8: snapshot only the log entry, not the customized-format flag
--- extra_init_by_lua
    local core = require("apisix.core")
    require("apisix.utils.log-util").inject_get_custom_format_log(function()
        return {nothing = ngx.null, empty = setmetatable({}, core.json.array_mt)}
    end)
    require("apisix.utils.batch-processor-manager").add_entry = function(_, _, entry)
        local body = assert(core.json.decode(entry.body))
        ngx.say("null preserved: ", body.nothing == ngx.null)
        ngx.say("array preserved: ", getmetatable(body.empty) == core.json.array_mt)
        return true
    end
--- config
    location /t {
        content_by_lua_block {
            require("apisix.plugins.elasticsearch-logger").log({
                field = {index = "snapshot"},
                log_format = {}
            }, {var = {}})
        }
    }
--- response_body
null preserved: true
array preserved: true



=== TEST 9: a snapshot encoding failure is not queued
--- extra_init_by_lua
    require("apisix.utils.log-util").inject_get_custom_format_log(function()
        return {invalid = function() end}
    end)
    require("apisix.utils.batch-processor-manager").add_entry = function()
        error("invalid snapshot must not be queued")
    end
--- config
    location /t {
        content_by_lua_block {
            require("apisix.plugins.elasticsearch-logger").log({
                field = {index = "snapshot"},
                log_format = {}
            }, {var = {}})
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
failed to encode Elasticsearch log entry:
--- no_error_log
[alert]



=== TEST 10: response-rewrite preserves its body rewrite when 404 becomes 200
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/specific_status",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1}
                },
                plugins = {
                    ["response-rewrite"] = {
                        _meta = {filter = {{"status", "==", 404}}},
                        status_code = 200,
                        body = "replacement body"
                    }
                }
            })
            assert(code < 300, body)
            local res = assert(require("resty.http").new():request_uri(
                "http://127.0.0.1:1984/specific_status", {
                    headers = {["x-test-upstream-status"] = "404"}
                }))
            ngx.say(res.status)
            ngx.say(res.body)
        }
    }
--- response_body
200
replacement body
