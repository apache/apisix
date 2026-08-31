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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 127.0.0.1:16724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    ngx.say([[{"choices":[{"message":{"content":"ok","role":"assistant"}}]}]])
                }
            }

            location /status {
                content_by_lua_block {
                    ngx.say("ok")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: report the active health check status of each ai-proxy-multi instance
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local http = require("resty.http")

            local checks = {
                active = {
                    timeout = 1,
                    http_path = "/status",
                    healthy = {
                        interval = 1,
                        successes = 1,
                    },
                    unhealthy = {
                        interval = 1,
                        http_failures = 1,
                        tcp_failures = 1,
                        timeouts = 1,
                    },
                },
            }

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "openai-healthy",
                                provider = "openai",
                                weight = 1,
                                priority = 1,
                                auth = {header = {Authorization = "Bearer token"}},
                                options = {model = "gpt-4"},
                                override = {endpoint = "http://127.0.0.1:16724"},
                                checks = checks,
                            },
                            {
                                name = "openai-unhealthy",
                                provider = "openai",
                                weight = 1,
                                priority = 0,
                                auth = {header = {Authorization = "Bearer token"}},
                                options = {model = "gpt-4"},
                                override = {endpoint = "http://127.0.0.1:16725"},
                                checks = checks,
                            },
                        },
                        ssl_verify = false,
                    },
                },
            }

            local code, body = t.test("/apisix/admin/routes/1", ngx.HTTP_PUT,
                                      json.encode(route))
            assert(code < 300, body)

            -- the checkers are created on demand, so the route has to be hit once
            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/ai",
                {
                    method = "POST",
                    body = json.encode({messages = {{role = "user", content = "hi"}}}),
                    headers = {["Content-Type"] = "application/json"},
                }
            )
            assert(res, err)
            assert(res.status == 200, "unexpected status: " .. tostring(res.status))

            ngx.sleep(3)

            local code, body, res = t.test("/v1/healthcheck", ngx.HTTP_GET)
            assert(code == 200, body)
            res = json.decode(res)

            local infos = {}
            for _, info in ipairs(res) do
                if info.plugin and info.name:find("/routes/1#", 1, true) then
                    table.insert(infos, info)
                end
            end
            table.sort(infos, function(a, b) return a.name < b.name end)

            for _, info in ipairs(infos) do
                ngx.say(info.name, " plugin=", info.plugin, " instance=", info.meta.instance,
                        " type=", info.type, " nodes=", #info.nodes,
                        " ", info.nodes[1].ip, ":", info.nodes[1].port,
                        " ", info.nodes[1].status)
            end
        }
    }
--- response_body
/apisix/routes/1#plugins['ai-proxy-multi'].instances[0] plugin=ai-proxy-multi instance=openai-healthy type=http nodes=1 127.0.0.1:16724 healthy
/apisix/routes/1#plugins['ai-proxy-multi'].instances[1] plugin=ai-proxy-multi instance=openai-unhealthy type=http nodes=1 127.0.0.1:16725 unhealthy
--- timeout: 10



=== TEST 2: plugin instance checkers coexist with upstream checkers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local http = require("resty.http")

            local checks = {
                active = {
                    timeout = 1,
                    http_path = "/status",
                    healthy = {
                        interval = 1,
                        successes = 1,
                    },
                    unhealthy = {
                        interval = 1,
                        http_failures = 1,
                        tcp_failures = 1,
                        timeouts = 1,
                    },
                },
            }

            local route = {
                uri = "/ai",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "openai-first",
                                provider = "openai",
                                weight = 1,
                                priority = 1,
                                auth = {header = {Authorization = "Bearer token"}},
                                options = {model = "gpt-4"},
                                override = {endpoint = "http://127.0.0.1:16724"},
                                checks = checks,
                            },
                            {
                                name = "openai-second",
                                provider = "openai",
                                weight = 1,
                                priority = 0,
                                auth = {header = {Authorization = "Bearer token"}},
                                options = {model = "gpt-4"},
                                override = {endpoint = "http://127.0.0.1:16724"},
                                checks = checks,
                            },
                        },
                        ssl_verify = false,
                    },
                },
            }

            local code, body = t.test("/apisix/admin/routes/1", ngx.HTTP_PUT,
                                      json.encode(route))
            assert(code < 300, body)

            code, body = t.test("/apisix/admin/routes/2", ngx.HTTP_PUT, json.encode({
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1},
                    checks = checks,
                },
            }))
            assert(code < 300, body)

            for _, uri in ipairs({"/ai", "/hello"}) do
                local httpc = http.new()
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. uri,
                    {
                        method = "POST",
                        body = json.encode({messages = {{role = "user", content = "hi"}}}),
                        headers = {["Content-Type"] = "application/json"},
                    }
                )
                assert(res, err)
            end

            ngx.sleep(3)

            local code, body, res = t.test("/v1/healthcheck", ngx.HTTP_GET)
            assert(code == 200, body)
            res = json.decode(res)

            local infos = {}
            for _, info in ipairs(res) do
                if info.name:find("/routes/1", 1, true)
                   or info.name:find("/routes/2", 1, true) then
                    table.insert(infos, info)
                end
            end
            table.sort(infos, function(a, b) return a.name < b.name end)

            for _, info in ipairs(infos) do
                ngx.say(info.name, " plugin=", tostring(info.plugin),
                        " nodes=", #info.nodes)
            end
        }
    }
--- response_body
/apisix/routes/1#plugins['ai-proxy-multi'].instances[0] plugin=ai-proxy-multi nodes=1
/apisix/routes/1#plugins['ai-proxy-multi'].instances[1] plugin=ai-proxy-multi nodes=1
/apisix/routes/2 plugin=nil nodes=1
--- timeout: 10



=== TEST 3: disable_upstream_healthcheck stops probing the plugin instances too
--- yaml_config
apisix:
    disable_upstream_healthcheck: true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local http = require("resty.http")

            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/ai",
                {
                    method = "POST",
                    body = json.encode({messages = {{role = "user", content = "hi"}}}),
                    headers = {["Content-Type"] = "application/json"},
                }
            )
            assert(res, err)

            ngx.sleep(3)

            -- the entries stay listed, but no checker was ever created, so every
            -- node list is empty -- the same as for a plain upstream checker
            local code, body, res = t.test("/v1/healthcheck", ngx.HTTP_GET)
            assert(code == 200, body)
            res = json.decode(res)
            local probed = 0
            for _, info in ipairs(res) do
                probed = probed + #info.nodes
            end
            ngx.say("probed nodes: ", probed)

            local code, body, res = t.test("/v1/healthcheck/routes/1/checkers", ngx.HTTP_GET)
            assert(code == 200, body)
            res = json.decode(res)
            probed = 0
            for _, info in ipairs(res) do
                probed = probed + #info.nodes
            end
            ngx.say("checkers: ", #res, " probed nodes: ", probed)
        }
    }
--- response_body
probed nodes: 0
checkers: 2 probed nodes: 0
--- timeout: 10



=== TEST 4: instances are listed before the checkers have probed anything
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")

            local checks = {
                active = {
                    timeout = 1,
                    http_path = "/status",
                    healthy = {
                        interval = 1,
                        successes = 1,
                    },
                    unhealthy = {
                        interval = 1,
                        http_failures = 1,
                        tcp_failures = 1,
                        timeouts = 1,
                    },
                },
            }

            local instances = {}
            for _, name in ipairs({"openai-a", "openai-b"}) do
                table.insert(instances, {
                    name = name,
                    provider = "openai",
                    weight = 1,
                    auth = {header = {Authorization = "Bearer token"}},
                    options = {model = "gpt-4"},
                    override = {endpoint = "http://127.0.0.1:16724"},
                    checks = checks,
                })
            end

            local code, body = t.test("/apisix/admin/routes/3", ngx.HTTP_PUT, json.encode({
                uri = "/ai-untouched",
                plugins = {
                    ["ai-proxy-multi"] = {
                        instances = instances,
                        ssl_verify = false,
                    },
                },
            }))
            assert(code < 300, body)

            -- give the route time to reach the worker, but never send a request
            ngx.sleep(1)

            local code, body, res = t.test("/v1/healthcheck", ngx.HTTP_GET)
            assert(code == 200, body)
            res = json.decode(res)

            local infos = {}
            for _, info in ipairs(res) do
                if info.name:find("/routes/3#", 1, true) then
                    table.insert(infos, info)
                end
            end
            table.sort(infos, function(a, b) return a.name < b.name end)

            for _, info in ipairs(infos) do
                ngx.say(info.name, " instance=", info.meta.instance,
                        " type=", info.type, " nodes=", #info.nodes)
            end
        }
    }
--- response_body
/apisix/routes/3#plugins['ai-proxy-multi'].instances[0] instance=openai-a type=http nodes=0
/apisix/routes/3#plugins['ai-proxy-multi'].instances[1] instance=openai-b type=http nodes=0
--- timeout: 10



=== TEST 5: the checkers sub-resource lists every checker of an AI route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local http = require("resty.http")

            local checks = {
                active = {
                    timeout = 1,
                    http_path = "/status",
                    healthy = {
                        interval = 1,
                        successes = 1,
                    },
                    unhealthy = {
                        interval = 1,
                        http_failures = 1,
                        tcp_failures = 1,
                        timeouts = 1,
                    },
                },
            }

            local code, body = t.test("/apisix/admin/routes/4", ngx.HTTP_PUT, json.encode({
                uri = "/ai4",
                plugins = {
                    ["ai-proxy-multi"] = {
                        fallback_strategy = "instance_health_and_rate_limiting",
                        instances = {
                            {
                                name = "openai-up",
                                provider = "openai",
                                weight = 1,
                                priority = 1,
                                auth = {header = {Authorization = "Bearer token"}},
                                options = {model = "gpt-4"},
                                override = {endpoint = "http://127.0.0.1:16724"},
                                checks = checks,
                            },
                            {
                                name = "openai-down",
                                provider = "openai",
                                weight = 1,
                                priority = 0,
                                auth = {header = {Authorization = "Bearer token"}},
                                options = {model = "gpt-4"},
                                override = {endpoint = "http://127.0.0.1:16725"},
                                checks = checks,
                            },
                        },
                        ssl_verify = false,
                    },
                },
            }))
            assert(code < 300, body)

            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/ai4",
                {
                    method = "POST",
                    body = json.encode({messages = {{role = "user", content = "hi"}}}),
                    headers = {["Content-Type"] = "application/json"},
                }
            )
            assert(res, err)
            assert(res.status == 200, "unexpected status: " .. tostring(res.status))

            ngx.sleep(3)

            local code, body, res = t.test("/v1/healthcheck/routes/4/checkers", ngx.HTTP_GET)
            assert(code == 200, body)
            res = json.decode(res)
            table.sort(res, function(a, b) return a.name < b.name end)

            for _, info in ipairs(res) do
                ngx.say(info.name, " plugin=", info.plugin,
                        " instance=", info.meta.instance,
                        " type=", info.type,
                        " ", info.nodes[1].ip, ":", info.nodes[1].port,
                        " ", info.nodes[1].status)
            end
        }
    }
--- response_body
/apisix/routes/4#plugins['ai-proxy-multi'].instances[0] plugin=ai-proxy-multi instance=openai-up type=http 127.0.0.1:16724 healthy
/apisix/routes/4#plugins['ai-proxy-multi'].instances[1] plugin=ai-proxy-multi instance=openai-down type=http 127.0.0.1:16725 unhealthy
--- timeout: 10



=== TEST 6: the checkers sub-resource reports a plain upstream checker too
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local http = require("resty.http")

            local code, body = t.test("/apisix/admin/routes/5", ngx.HTTP_PUT, json.encode({
                uri = "/hello5",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1},
                    checks = {
                        active = {
                            timeout = 1,
                            http_path = "/status",
                            healthy = {
                                interval = 1,
                                successes = 1,
                            },
                            unhealthy = {
                                interval = 1,
                                http_failures = 1,
                                tcp_failures = 1,
                                timeouts = 1,
                            },
                        },
                    },
                },
            }))
            assert(code < 300, body)

            local httpc = http.new()
            local res, err = httpc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/hello5",
                {method = "GET"}
            )
            assert(res, err)

            ngx.sleep(3)

            local code, body, res = t.test("/v1/healthcheck/routes/5/checkers", ngx.HTTP_GET)
            assert(code == 200, body)
            res = json.decode(res)

            for _, info in ipairs(res) do
                ngx.say(info.name, " plugin=", tostring(info.plugin),
                        " meta=", tostring(info.meta),
                        " type=", info.type, " nodes=", #info.nodes)
            end

            -- the single-object endpoint keeps returning exactly one checker
            local code, body, res = t.test("/v1/healthcheck/routes/5", ngx.HTTP_GET)
            assert(code == 200, body)
            res = json.decode(res)
            ngx.say("single: ", res.name, " nodes=", #res.nodes)
        }
    }
--- response_body
/apisix/routes/5 plugin=nil meta=nil type=http nodes=1
single: /apisix/routes/5 nodes=1
--- timeout: 10



=== TEST 7: a resource without health checks owns an empty checker set
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")

            local code, body = t.test("/apisix/admin/routes/6", ngx.HTTP_PUT, json.encode({
                uri = "/hello6",
                upstream = {
                    type = "roundrobin",
                    nodes = {["127.0.0.1:1980"] = 1},
                },
            }))
            assert(code < 300, body)

            local function trim(s)
                return (tostring(s):gsub("%s+$", ""))
            end

            local code, body, res = t.test("/v1/healthcheck/routes/6/checkers", ngx.HTTP_GET)
            ngx.say("no checks: ", code, " ", trim(res))

            -- the single-object endpoint still reports this as an error
            local code, body = t.test("/v1/healthcheck/routes/6", ngx.HTTP_GET)
            ngx.say("single: ", code, " ", trim(body))

            local code, body = t.test("/v1/healthcheck/routes/404/checkers", ngx.HTTP_GET)
            ngx.say("missing: ", code, " ", trim(body))

            local code, body = t.test("/v1/healthcheck/routes/6/nodes", ngx.HTTP_GET)
            ngx.say("bad sub resource: ", code, " ", trim(body))
        }
    }
--- response_body
no checks: 200 []
single: 404 {"error_msg":"no checker for routes[6]"}
missing: 404 {"error_msg":"routes[404] not found"}
bad sub resource: 400 {"error_msg":"invalid sub resource nodes"}
--- timeout: 10



=== TEST 8: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            for _, id in ipairs({1, 2, 3, 4, 5, 6}) do
                local code, body = t.test("/apisix/admin/routes/" .. id, ngx.HTTP_DELETE)
                assert(code < 300, body)
            end
            ngx.say("passed")
        }
    }
--- response_body
passed
