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
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: set up the same serverless conf on a plugin_config, a consumer and routes
# Every route below ends up running a serverless-post-function with the same
# conf, which reports the conf_version of its own conf. They are separate
# tables, and the request-time writes of the core onto them differ: a plugin
# with a custom priority on the route, a merge with consumer plugins, an
# authentication that passes or fails. /ref is the reference that none of them
# touches.
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local report = {
                phase = "header_filter",
                functions = {
                    "return function(conf, ctx) ngx.header['X-Conf-Version'] = "
                    .. "require('apisix.plugin').conf_version(conf) end"
                },
            }
            local rewrite = {uri = "/hello"}
            local upstream = {
                type = "roundrobin",
                nodes = {["127.0.0.1:1980"] = 1},
            }

            local resources = {
                {"/apisix/admin/plugin_configs/1", {
                    plugins = {["serverless-post-function"] = report},
                }},
                {"/apisix/admin/consumers", {
                    username = "jack",
                    plugins = {
                        ["key-auth"] = {key = "jack-key"},
                        ["serverless-post-function"] = report,
                    },
                }},
                {"/apisix/admin/consumers", {
                    username = "rose",
                    plugins = {
                        ["key-auth"] = {key = "rose-key"},
                        ["response-rewrite"] = {headers = {set = {["X-Consumer"] = "rose"}}},
                    },
                }},
                {"/apisix/admin/routes/ref", {
                    uri = "/ref",
                    upstream = upstream,
                    plugins = {
                        ["proxy-rewrite"] = rewrite,
                        ["serverless-post-function"] = report,
                    },
                }},
                -- shares plugin_config 1 and sorts its plugins by priority
                {"/apisix/admin/routes/priority", {
                    uri = "/priority",
                    upstream = upstream,
                    plugin_config_id = 1,
                    plugins = {
                        ["proxy-rewrite"] = {uri = "/hello", _meta = {priority = 10000}},
                    },
                }},
                -- shares plugin_config 1 without any custom priority
                {"/apisix/admin/routes/plain", {
                    uri = "/plain",
                    upstream = upstream,
                    plugin_config_id = 1,
                    plugins = {["proxy-rewrite"] = rewrite},
                }},
                -- jack brings the serverless conf through the consumer merge
                {"/apisix/admin/routes/consumer", {
                    uri = "/consumer",
                    upstream = upstream,
                    plugins = {
                        ["key-auth"] = {},
                        ["proxy-rewrite"] = rewrite,
                    },
                }},
                -- rose brings another plugin, so the serverless conf of the route
                -- goes through the rewrite_in_consumer phase
                {"/apisix/admin/routes/auth", {
                    uri = "/auth",
                    upstream = upstream,
                    plugins = {
                        ["key-auth"] = {},
                        ["proxy-rewrite"] = rewrite,
                        ["serverless-post-function"] = report,
                    },
                }},
            }

            for _, res in ipairs(resources) do
                local code, body = t(res[1], ngx.HTTP_PUT, core.json.encode(res[2]))
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: a plugin with a custom priority does not change the version of a shared conf
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            local versions = {}
            for _, path in ipairs({"/priority", "/plain", "/ref"}) do
                local res = assert(http.new():request_uri(uri .. path))
                if res.status ~= 200 then
                    ngx.say(path, ": ", res.status)
                end
                versions[path] = res.headers["X-Conf-Version"]
            end

            local ref = versions["/ref"]
            ngx.say("priority: ", ref ~= nil and versions["/priority"] == ref)
            ngx.say("plain: ", ref ~= nil and versions["/plain"] == ref)
        }
    }
--- response_body
priority: true
plain: true



=== TEST 3: the same in the other request order
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            local versions = {}
            for _, path in ipairs({"/plain", "/priority", "/ref"}) do
                local res = assert(http.new():request_uri(uri .. path))
                if res.status ~= 200 then
                    ngx.say(path, ": ", res.status)
                end
                versions[path] = res.headers["X-Conf-Version"]
            end

            local ref = versions["/ref"]
            ngx.say("priority: ", ref ~= nil and versions["/priority"] == ref)
            ngx.say("plain: ", ref ~= nil and versions["/plain"] == ref)
        }
    }
--- response_body
priority: true
plain: true



=== TEST 4: a conf merged from the consumer keeps its version
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            local res = assert(http.new():request_uri(uri .. "/consumer",
                                                      {headers = {apikey = "jack-key"}}))
            local consumer = res.headers["X-Conf-Version"]
            res = assert(http.new():request_uri(uri .. "/ref"))

            ngx.say("status: ", res.status)
            ngx.say("consumer: ", consumer ~= nil and consumer == res.headers["X-Conf-Version"])
        }
    }
--- response_body
status: 200
consumer: true



=== TEST 5: a route conf keeps its version whether the first request passes authentication
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            local res = assert(http.new():request_uri(uri .. "/auth",
                                                      {headers = {apikey = "rose-key"}}))
            ngx.say("authenticated: ", res.status, " ", res.headers["X-Consumer"])
            local authenticated = res.headers["X-Conf-Version"]

            res = assert(http.new():request_uri(uri .. "/ref"))
            local ref = res.headers["X-Conf-Version"]
            ngx.say("ref: ", res.status)
            ngx.say("same: ", ref ~= nil and authenticated == ref)
        }
    }
--- response_body
authenticated: 200 rose
ref: 200
same: true



=== TEST 6: the same when the first request fails authentication
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            local res = assert(http.new():request_uri(uri .. "/auth",
                                                      {headers = {apikey = "bad-key"}}))
            ngx.say("rejected: ", res.status)
            local rejected = res.headers["X-Conf-Version"]

            res = assert(http.new():request_uri(uri .. "/auth",
                                                {headers = {apikey = "rose-key"}}))
            ngx.say("authenticated: ", res.status)
            local authenticated = res.headers["X-Conf-Version"]

            res = assert(http.new():request_uri(uri .. "/ref"))
            ngx.say("ref: ", res.status)
            local ref = res.headers["X-Conf-Version"]
            ngx.say("rejected: ", ref ~= nil and rejected == ref)
            ngx.say("authenticated: ", ref ~= nil and authenticated == ref)
        }
    }
--- response_body
rejected: 401
authenticated: 200
ref: 200
rejected: true
authenticated: true



=== TEST 7: runtime state reads through the conf but stays out of its encoding
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugin")

            local conf = {key = "v", _meta = {priority = 5}}
            local version = plugin.conf_version(conf)

            plugin.set_runtime_state(conf, "_from_consumer", true)
            ngx.say("read: ", conf._from_consumer, " ", conf._version == version)
            local ok, err = pcall(plugin.set_runtime_state, conf._meta, "priority", 1)
            ngx.say("unprefixed key: ", ok, " ", err, " ", conf._meta.priority)
            ngx.say("encoded: ", core.json.stably_encode(conf))

            -- a deep copy reads the state it was copied with and then keeps its own
            local copy = core.table.deepcopy(conf)
            ngx.say("copy reads: ", copy._from_consumer)
            plugin.set_runtime_state(copy, "_from_consumer", false)
            plugin.set_runtime_state(copy, "_dns_nodes", {})
            ngx.say("copy: ", copy._from_consumer, " ", copy._version == version)
            ngx.say("origin: ", conf._from_consumer, " ", conf._dns_nodes)

            -- a nil clears the state of the copy only
            plugin.set_runtime_state(copy, "_version", nil)
            ngx.say("cleared: ", copy._version, " ", conf._version == version)

            -- an object decoded as an empty array takes state, any other
            -- metatable the helper does not own is never replaced
            local obj = setmetatable({key = "v"}, core.json.array_mt)
            plugin.set_runtime_state(obj, "_k", 1)
            ngx.say("empty array: ", obj._k, " ", core.json.stably_encode(obj))
            local arr = setmetatable({1}, core.json.array_mt)
            local ok, err = pcall(plugin.set_runtime_state, arr, "_k", 1)
            ngx.say("foreign metatable: ", ok, " ", err,
                    " ", getmetatable(arr) == core.json.array_mt)
        }
    }
--- response_body_like
read: true true
unprefixed key: false .*set_runtime_state: the key must start with '_': priority 5
encoded: \{"_meta":\{"priority":5\},"key":"v"\}
copy reads: true
copy: false true
origin: true nil
cleared: nil true
empty array: 1 \{"key":"v"\}
foreign metatable: false .*set_runtime_state: the table has a metatable of its own true



=== TEST 8: ai-proxy-multi keeps the resolved nodes of an instance out of the version
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local instance = function(name)
                return {
                    name = name,
                    provider = "openai",
                    weight = 1,
                    auth = {header = {Authorization = "Bearer token"}},
                    options = {model = "gpt-4"},
                    override = {endpoint = "http://127.0.0.1:1980/v1/chat/completions"},
                    checks = {
                        active = {
                            type = "http",
                            http_path = "/status",
                            healthy = {interval = 30, successes = 1},
                            unhealthy = {interval = 30, http_failures = 2},
                        },
                    },
                }
            end
            local ai = {instances = {instance("a"), instance("b")}}
            -- reports whether the ai-proxy-multi conf this request ran with has the
            -- version of the same conf on /ai-ref, which serves no request
            local compare = {
                phase = "header_filter",
                functions = {[[return function(conf, ctx)
                    local plugin = require("apisix.plugin")
                    local resource = require("apisix.resource")
                    local name = "ai-proxy-multi"
                    local ran = ctx.matched_route.value.plugins[name]
                    local ref_route = resource.fetch_latest_conf(ctx.matched_route.key .. "-ref")
                    local ref = ref_route.value.plugins[name]
                    ngx.header["X-Resolved"] = tostring(ran.instances[1]._dns_nodes ~= nil)
                    ngx.header["X-Same"] = tostring(plugin.conf_version(ran)
                                                  == plugin.conf_version(ref))
                end]]},
            }

            local routes = {
                {"/apisix/admin/routes/ai", {
                    uri = "/ai",
                    plugins = {["ai-proxy-multi"] = ai, ["serverless-post-function"] = compare},
                }},
                {"/apisix/admin/routes/ai-ref", {
                    uri = "/ai-ref",
                    plugins = {["ai-proxy-multi"] = ai},
                }},
            }
            for _, r in ipairs(routes) do
                local code, body = t(r[1], ngx.HTTP_PUT, core.json.encode(r[2]))
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end

            local http = require("resty.http")
            local res = assert(http.new():request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/ai", {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "openai/chat-basic.json",
                    },
                    body = [[{"messages":[{"role":"user","content":"hi"}]}]],
                }))
            ngx.say("resolved: ", res.headers["X-Resolved"])
            ngx.say("same: ", res.headers["X-Same"])
        }
    }
--- response_body
resolved: true
same: true
