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

=== TEST 1: set up routes whose plugins derive state from their conf at request time
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}}
            local routes = {
                cors = {
                    cors = {allow_origins_by_regex = {[[.*\.test$]]}},
                },
                ["uri-blocker"] = {
                    ["uri-blocker"] = {block_rules = {"^/nope"}, case_insensitive = true},
                },
                ["response-rewrite"] = {
                    ["response-rewrite"] = {
                        vars = {{"status", "==", 200}},
                        headers = {set = {["X-Rewritten"] = "1"}},
                    },
                },
                echo = {
                    echo = {headers = {["X-Echo"] = "1"}, before_body = "before "},
                    ["proxy-rewrite"] = {_meta = {priority = 10000}, uri = "/hello"},
                },
                ["traffic-label"] = {
                    ["traffic-label"] = {
                        rules = {{
                            match = {{"uri", "==", "/hello"}},
                            actions = {{set_headers = {["X-Label"] = "1"}}},
                        }},
                    },
                },
                ["traffic-split"] = {
                    ["traffic-split"] = {
                        rules = {{
                            weighted_upstreams = {{
                                upstream = {
                                    type = "roundrobin",
                                    nodes = {{host = "localhost", port = 1980, weight = 1}},
                                },
                                weight = 1,
                            }},
                        }},
                    },
                },
                ["forward-auth"] = {
                    ["forward-auth"] = {uri = "http://127.0.0.1:1980/hello"},
                },
                ["http-logger"] = {
                    ["http-logger"] = {
                        uri = "http://127.0.0.1:1980/log",
                        batch_max_size = 1,
                        include_req_body = true,
                        include_req_body_expr = {{"arg_bar", "==", "foo"}},
                        include_resp_body = true,
                        include_resp_body_expr = {{"arg_bar", "==", "foo"}},
                    },
                },
                ["authz-casbin"] = {
                    ["authz-casbin"] = {
                        model = [[
[request_definition]
r = sub, obj, act
[policy_definition]
p = sub, obj, act
[policy_effect]
e = some(where (p.eft == allow))
[matchers]
m = keyMatch(r.sub, p.sub) && keyMatch(r.obj, p.obj) && keyMatch(r.act, p.act)]],
                        policy = "p, *, /hello, GET",
                        username = "user",
                    },
                },
                ["oas-validator"] = {
                    ["oas-validator"] = {
                        spec = core.json.encode({
                            openapi = "3.0.0",
                            info = {title = "test", version = "1"},
                            paths = {["/hello"] = {get = {
                                responses = {["200"] = {description = "ok"}},
                            }}},
                        }),
                    },
                },
                workflow = {
                    workflow = {
                        rules = {{
                            case = {{"uri", "==", "/hello"}},
                            actions = {{"limit-count", {
                                count = 100,
                                time_window = 60,
                                rejected_code = 503,
                                key = "remote_addr",
                            }}},
                        }},
                    },
                },
                ["key-auth"] = {
                    ["key-auth"] = {},
                },
                ["key-auth-rewrite"] = {
                    ["key-auth"] = {},
                    ["response-rewrite"] = {headers = {set = {["X-Route"] = "1"}}},
                },
            }

            for name, plugins in pairs(routes) do
                local code, body = t('/apisix/admin/routes/' .. name, ngx.HTTP_PUT, {
                    uri = "/hello",
                    host = name .. ".test",
                    plugins = plugins,
                    upstream = upstream,
                })
                if code >= 300 then
                    ngx.status = code
                    ngx.say(name, ": ", body)
                    return
                end
            end

            -- a route with vars turns off the route cache of the ai plugin, which
            -- runs every route on a deep copy of it
            local code, body = t('/apisix/admin/routes/with-vars', ngx.HTTP_PUT, {
                uri = "/hello",
                host = "with-vars.test",
                vars = {{"arg_never", "==", "set"}},
                upstream = upstream,
            })
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/consumers', ngx.HTTP_PUT, {
                username = "jack",
                plugins = {
                    ["key-auth"] = {key = "auth-jack"},
                    ["response-rewrite"] = {headers = {set = {["X-Consumer"] = "jack"}}},
                    ["proxy-rewrite"] = {headers = {set = {["X-Consumer"] = "jack"}}},
                },
            })
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: requests leave every plugin conf as it was loaded
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local http = require("resty.http")

            local function snapshot()
                local confs = {}
                for _, key in ipairs({"/routes", "/consumers"}) do
                    local obj = core.config.fetch_created_obj(key)
                    for _, item in ipairs(obj.values) do
                        local id = item.value.id or item.value.username
                        for name, conf in pairs(item.value.plugins or {}) do
                            local ok, data = pcall(core.json.stably_encode, conf)
                            confs[key .. "/" .. id .. " " .. name] = ok and data
                                                                     or "error: " .. data
                        end
                    end
                end
                return confs
            end

            local before
            for _ = 1, 20 do
                before = snapshot()
                if core.table.nkeys(before) == 18 then
                    break
                end
                ngx.sleep(0.2)
            end

            local requests = {
                {host = "cors", headers = {Origin = "http://a.test"}},
                {host = "uri-blocker"},
                {host = "response-rewrite"},
                {host = "echo"},
                {host = "traffic-label"},
                {host = "traffic-split"},
                {host = "forward-auth"},
                {host = "authz-casbin", headers = {user = "alice"}},
                {host = "oas-validator"},
                {host = "workflow"},
                {host = "http-logger", query = "bar=foo"},
                {host = "key-auth-rewrite", headers = {apikey = "auth-jack"}},
                {host = "key-auth", headers = {apikey = "auth-jack"}},
                {host = "key-auth-rewrite", headers = {apikey = "auth-jack"}},
            }
            for _, req in ipairs(requests) do
                local headers = req.headers or {}
                headers.Host = req.host .. ".test"
                local httpc = http.new()
                local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port
                                                   .. "/hello", {
                    query = req.query,
                    headers = headers,
                })
                if not res then
                    ngx.say(req.host, ": ", err)
                    return
                end
                if res.status ~= 200 then
                    ngx.say(req.host, ": ", res.status)
                end
            end

            -- let the batch processor of http-logger run
            ngx.sleep(1.5)

            local after = snapshot()
            local keys = {}
            for key in pairs(before) do
                core.table.insert(keys, key)
            end
            table.sort(keys)
            for _, key in ipairs(keys) do
                if before[key] ~= after[key] then
                    ngx.say(key, " changed: ", before[key], " -> ", after[key])
                end
            end
            ngx.say("checked ", #keys, " confs")
        }
    }
--- response_body
checked 18 confs
--- timeout: 10



=== TEST 3: an empty plugin conf and an empty _meta load
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- an empty Lua table is sent as [], which is what the Admin API
            -- stores for an empty object
            local code, body = t('/apisix/admin/routes/empty', ngx.HTTP_PUT, {
                uri = "/hello",
                host = "empty.test",
                plugins = {
                    cors = {},
                    ["response-rewrite"] = {
                        _meta = {},
                        headers = {set = {["X-Empty-Meta"] = "1"}},
                    },
                },
                upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}},
            })
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: and run
--- request
GET /hello
--- more_headers
Host: empty.test
Origin: http://a.test
--- response_headers
Access-Control-Allow-Origin: *
X-Empty-Meta: 1
--- response_body
hello world
