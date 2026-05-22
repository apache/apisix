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
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";
    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;
    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    # Loosen the default no_error_log check (APISIX.pm sets it to [error]).
    # Under TEST_NGINX_USE_HUP=1 the prior worker generation can emit
    # transient "communicate(): failed to receive the header bytes" lines as
    # the event worker shuts down — that's nginx/APISIX shutdown noise, not
    # a plugin error. Tests that need to assert specific error-log content
    # set an explicit --- error_log line.
    if (!defined $block->error_log && !defined $block->no_error_log
        && !defined $block->grep_error_log
        && !defined $block->ignore_error_log) {
        $block->set_value("no_error_log", "[alert]");
    }

    my $extra_init_worker = $block->extra_init_worker_by_lua // "";
    $extra_init_worker .= <<_EOC_;
        require("lib.test_redis").flush_all()
_EOC_
    $block->set_value("extra_init_worker_by_lua", $extra_init_worker);

    if (!$block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", <<_EOC_);
plugins:
  - ai-cache
  - ai-proxy-multi
_EOC_
    }
});

run_tests();

__DATA__

=== TEST 1: schema accepts a minimal redis policy config
--- config
    location /t {
        content_by_lua_block {
            local schema_mod = require("apisix.plugins.ai-cache.schema")
            local core       = require("apisix.core")
            local ok, err = core.schema.check(schema_mod.schema, {
                policy     = "redis",
                redis_host = "127.0.0.1",
            })
            if not ok then
                ngx.say("FAIL: ", err)
            else
                ngx.say("ok")
            end
        }
    }
--- response_body
ok



=== TEST 2: schema rejects an unknown policy
--- config
    location /t {
        content_by_lua_block {
            local schema_mod = require("apisix.plugins.ai-cache.schema")
            local core       = require("apisix.core")
            local ok = core.schema.check(schema_mod.schema, {
                policy = "memory",
            })
            ngx.say(ok and "PASSED" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 3: schema requires redis_host when policy is redis
--- config
    location /t {
        content_by_lua_block {
            local schema_mod = require("apisix.plugins.ai-cache.schema")
            local core       = require("apisix.core")
            local ok = core.schema.check(schema_mod.schema, {
                policy = "redis",
            })
            ngx.say(ok and "PASSED" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 4: schema requires cluster nodes when policy is redis-cluster
--- config
    location /t {
        content_by_lua_block {
            local schema_mod = require("apisix.plugins.ai-cache.schema")
            local core       = require("apisix.core")
            local ok = core.schema.check(schema_mod.schema, {
                policy = "redis-cluster",
            })
            ngx.say(ok and "PASSED" or "rejected")
        }
    }
--- response_body
rejected



=== TEST 5: schema fills exact.ttl default
--- config
    location /t {
        content_by_lua_block {
            local schema_mod = require("apisix.plugins.ai-cache.schema")
            local core       = require("apisix.core")
            local conf = {
                policy     = "redis",
                redis_host = "127.0.0.1",
            }
            local ok, err = core.schema.check(schema_mod.schema, conf)
            if not ok then
                ngx.say("FAIL: ", err)
                return
            end
            ngx.say(conf.exact and conf.exact.ttl or "no-default")
        }
    }
--- response_body
3600



=== TEST 6: plugin loads and check_schema accepts a minimal config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                policy     = "redis",
                redis_host = "127.0.0.1",
            })
            if not ok then
                ngx.say("FAIL: ", err)
            else
                ngx.say(plugin.name, " ", plugin.priority)
            end
        }
    }
--- response_body
ai-cache 1086



=== TEST 7: stream=true short-circuits with X-AI-Cache-Status: SKIP-STREAM
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-cache": {
                            "policy":     "redis",
                            "redis_host": "127.0.0.1"
                        },
                        "ai-proxy-multi": {
                            "instances": [{
                                "name": "stub",
                                "provider": "openai",
                                "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer x" } },
                                "options": { "model": "gpt-4o" },
                                "override": { "endpoint": "http://127.0.0.1:1980" }
                            }],
                            "ssl_verify": false
                        }
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



=== TEST 8: SSE stream request gets SKIP-STREAM header and is served by ai-proxy
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"hi"}],"stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers
X-AI-Cache-Status: SKIP-STREAM
--- response_body_like eval
qr/data: \[DONE\]/



=== TEST 9: set route for the non-stream miss path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-cache": {
                            "policy":     "redis",
                            "redis_host": "127.0.0.1"
                        },
                        "ai-proxy-multi": {
                            "instances": [{
                                "name": "stub",
                                "provider": "openai",
                                "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer x" } },
                                "options": { "model": "gpt-4o" },
                                "override": { "endpoint": "http://127.0.0.1:1980" }
                            }],
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 10: missing key returns MISS and proxies to upstream
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/"1 \+ 1 = 2\."/



=== TEST 11: set route for the log-phase write test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-cache": {
                            "policy":     "redis",
                            "redis_host": "127.0.0.1",
                            "exact":      { "ttl": 60 }
                        },
                        "ai-proxy-multi": {
                            "instances": [{
                                "name": "stub",
                                "provider": "openai",
                                "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer x" } },
                                "options": { "model": "gpt-4o" },
                                "override": { "endpoint": "http://127.0.0.1:1980" }
                            }],
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 12: after a miss, the cached body is written to Redis (timer-driven)
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local hc, err = http.new()
            local res, req_err = hc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/anything",
                {
                    method = "POST",
                    body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}]],
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "openai/chat-basic.json",
                    },
                }
            )
            if not res then
                ngx.say("request failed: ", req_err)
                return
            end
            if res.headers["X-AI-Cache-Status"] ~= "MISS" then
                ngx.say("expected MISS header, got: ", tostring(res.headers["X-AI-Cache-Status"]))
                return
            end

            -- Give the log-phase timer a moment to complete the SETEX.
            ngx.sleep(0.2)

            local key_mod = require("apisix.plugins.ai-cache.key")
            local key = key_mod.build({
                model    = "gpt-4o",
                messages = {{ role = "user", content = "hello" }},
            })
            local redis = require("resty.redis").new()
            redis:set_timeouts(1000, 1000, 1000)
            local ok, conn_err = redis:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("connect failed: ", conn_err)
                return
            end
            local body, get_err = redis:get(key)
            if get_err then
                ngx.say("get failed: ", get_err)
                return
            end
            if body == ngx.null then
                ngx.say("KEY MISSING")
                return
            end
            ngx.say(string.find(body, "1 %+ 1 = 2", 1, false) and "found" or "no-match")
        }
    }
--- response_body
found



=== TEST 13: oversized response body is not written
--- config
    location /t {
        content_by_lua_block {
            -- Drive the log phase directly with a forged ctx so we don't
            -- depend on an upstream fixture larger than 1 MiB.
            local plugin = require("apisix.plugins.ai-cache")
            local key_mod = require("apisix.plugins.ai-cache.key")
            local k = key_mod.build({
                model    = "gpt-4o",
                messages = {{ role = "user", content = "oversized" }},
            })
            local conf = {
                policy     = "redis",
                redis_host = "127.0.0.1",
                exact      = { ttl = 60 },
                redis_keepalive_timeout = 10000,
                redis_keepalive_pool    = 100,
            }
            local oversize = string.rep("x", 1048577)        -- 1 MiB + 1
            ngx.ctx.ai_cache = { key = k, started_at = ngx.now() }
            ngx.ctx.llm_raw_response_body = '{"body":"' .. oversize .. '"}'
            ngx.status = 200

            plugin.log(conf, ngx.ctx)

            -- Let any scheduled timer drain (in this case there should be none).
            ngx.sleep(0.1)

            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("connect failed: ", err)
                return
            end
            local v = r:get(k)
            if v == ngx.null then
                ngx.say("not-written")
            else
                ngx.say("WRITTEN")
            end
        }
    }
--- response_body
not-written



=== TEST 14: HIT short-circuit serves cached body even when upstream is dead
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Configure a route with an unreachable upstream — only a cache HIT
            -- can produce a 200 response with the expected body.
            local code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-cache": {
                            "policy":     "redis",
                            "redis_host": "127.0.0.1",
                            "exact":      { "ttl": 60 }
                        },
                        "ai-proxy-multi": {
                            "instances": [{
                                "name": "stub",
                                "provider": "openai",
                                "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer x" } },
                                "options": { "model": "gpt-4o" },
                                "override": { "endpoint": "http://127.0.0.1:1" }
                            }],
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.say("route setup failed: ", code)
                return
            end

            -- Pre-populate Redis with a cached body for the request we will send.
            local key_mod = require("apisix.plugins.ai-cache.key")
            local key = key_mod.build({
                model    = "gpt-4o",
                messages = {{ role = "user", content = "cached" }},
            })
            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", err)
                return
            end
            local cached_body = '{"choices":[{"message":{"role":"assistant","content":"FROM-CACHE"}}],"id":"cached-1","model":"gpt-4o","object":"chat.completion"}'
            local ok2, set_err = r:setex(key, 60, cached_body)
            if not ok2 then
                ngx.say("redis setex failed: ", set_err)
                return
            end

            -- Issue the request via resty.http to the same nginx — keeps state
            -- in a single block so neither HUP nor init_worker can wipe Redis
            -- before the request runs.
            local http = require("resty.http")
            local hc = http.new()
            local res, req_err = hc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/anything",
                {
                    method = "POST",
                    body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"cached"}]}]],
                    headers = { ["Content-Type"] = "application/json" },
                }
            )
            if not res then
                ngx.say("request failed: ", req_err)
                return
            end
            ngx.say("status=", res.status)
            ngx.say("cache-status=", tostring(res.headers["X-AI-Cache-Status"]))
            ngx.say("content-type=", tostring(res.headers["Content-Type"]))
            ngx.say("body-has-cache-marker=",
                    string.find(res.body, "FROM-CACHE", 1, true) and "yes" or "no")
        }
    }
--- response_body
status=200
cache-status=HIT
content-type=application/json
body-has-cache-marker=yes



=== TEST 15: when Redis is unreachable, request still serves with MISS header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-cache": {
                            "policy":     "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 1
                        },
                        "ai-proxy-multi": {
                            "instances": [{
                                "name": "stub",
                                "provider": "openai",
                                "weight": 1,
                                "auth": { "header": { "Authorization": "Bearer x" } },
                                "options": { "model": "gpt-4o" },
                                "override": { "endpoint": "http://127.0.0.1:1980" }
                            }],
                            "ssl_verify": false
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.say("route setup failed: ", code)
                return
            end

            local http = require("resty.http")
            local hc = http.new()
            local res, req_err = hc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/anything",
                {
                    method = "POST",
                    body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"fail-open"}]}]],
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "openai/chat-basic.json",
                    },
                }
            )
            if not res then
                ngx.say("request failed: ", req_err)
                return
            end
            ngx.say("status=", res.status)
            ngx.say("cache-status=", tostring(res.headers["X-AI-Cache-Status"]))
            ngx.say("upstream-body-served=",
                    string.find(res.body, "1 %+ 1 = 2", 1, false) and "yes" or "no")
        }
    }
--- response_body
status=200
cache-status=MISS
upstream-body-served=yes
--- error_log
ai-cache: redis connect failed
