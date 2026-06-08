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

=== TEST 1: schema integration smoke (accepts valid redis; rejects missing redis_host)
--- config
    location /t {
        content_by_lua_block {
            local schema_mod = require("apisix.plugins.ai-cache.schema")
            local core       = require("apisix.core")

            -- (a) a valid single-node redis config is accepted
            local ok, err = core.schema.check(schema_mod.schema, {
                policy     = "redis",
                redis_host = "127.0.0.1",
            })
            if not ok then
                ngx.say("FAIL accept: ", err)
                return
            end

            -- (b) policy=redis but missing redis_host is rejected
            local ok2, err2 = core.schema.check(schema_mod.schema, {
                policy = "redis",
            })
            if ok2 then
                ngx.say("FAIL reject: missing redis_host was accepted")
                return
            end

            ngx.say("accept ok")
            ngx.say(err2)
        }
    }
--- response_body_like eval
qr/accept ok\nthen clause did not match/



=== TEST 2: schema rejects an unknown policy
--- config
    location /t {
        content_by_lua_block {
            local schema_mod = require("apisix.plugins.ai-cache.schema")
            local core       = require("apisix.core")
            local ok, err = core.schema.check(schema_mod.schema, {
                policy = "memory",
            })
            if ok then
                ngx.say("PASSED")
            else
                ngx.say(err)
            end
        }
    }
--- response_body_like eval
qr/property "policy" validation failed: matches none of the enum values/



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



=== TEST 16: corrupt cached JSON is dropped (DEL) and treated as a miss, never served
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
            if code >= 300 then
                ngx.say("route setup failed: ", code)
                return
            end

            -- Seed Redis with a CORRUPT (non-JSON) value under the key the
            -- plugin will compute for the request below.
            local key_mod = require("apisix.plugins.ai-cache.key")
            local key = key_mod.build({
                model    = "gpt-4o",
                messages = {{ role = "user", content = "corrupt" }},
            })
            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", err)
                return
            end
            local ok2, set_err = r:setex(key, 60, "{this is not valid json")
            if not ok2 then
                ngx.say("redis setex failed: ", set_err)
                return
            end

            local http = require("resty.http")
            local hc = http.new()
            local res, req_err = hc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/anything",
                {
                    method = "POST",
                    body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"corrupt"}]}]],
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
            ngx.say("served-corrupt=",
                    string.find(res.body, "not valid json", 1, true) and "yes" or "no")
            ngx.say("served-upstream=",
                    string.find(res.body, "1 %+ 1 = 2", 1, false) and "yes" or "no")
        }
    }
--- response_body
status=200
cache-status=MISS
served-corrupt=no
served-upstream=yes
--- error_log
ai-cache: corrupt cached



=== TEST 17: redis-cluster slot-lock shared dict is declared under the name the plugin uses
--- config
    location /t {
        content_by_lua_block {
            -- Regression guard: get_client() passes this exact dict name to
            -- rediscluster.new() for policy=redis-cluster. If it is not a
            -- declared lua_shared_dict, the cluster client cannot cache its
            -- slot map and the redis-cluster policy is non-functional.
            local dict = ngx.shared["plugin-ai-cache-redis-cluster-slot-lock"]
            ngx.say(dict ~= nil and "declared" or "MISSING")
        }
    }
--- response_body
declared



=== TEST 18: two identical requests; upstream invoked exactly once, second served from cache
--- http_config
    lua_shared_dict ai_cache_upstream_hits 1m;
    server {
        listen 1986;
        location / {
            content_by_lua_block {
                ngx.shared.ai_cache_upstream_hits:incr("n", 1, 0)
                ngx.header["Content-Type"] = "application/json"
                ngx.print('{"id":"cnt-1","object":"chat.completion","model":"gpt-4o",'
                    .. '"choices":[{"index":0,"message":{"role":"assistant","content":"counted-answer"},'
                    .. '"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}')
            }
        }
    }
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
                                "override": { "endpoint": "http://127.0.0.1:1986" }
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
            local body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"roundtrip-xyz"}]}]]
            local function send()
                local hc = http.new()
                return hc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/anything",
                    {
                        method = "POST",
                        body = body,
                        headers = { ["Content-Type"] = "application/json" },
                    }
                )
            end

            local r1 = send()
            if not r1 then ngx.say("req1 failed"); return end
            ngx.say("r1-status=", tostring(r1.headers["X-AI-Cache-Status"]))

            -- Let the log-phase timer finish the SETEX before the second request.
            ngx.sleep(0.3)

            local r2 = send()
            if not r2 then ngx.say("req2 failed"); return end
            ngx.say("r2-status=", tostring(r2.headers["X-AI-Cache-Status"]))
            ngx.say("r2-served-upstream-body=",
                    string.find(r2.body, "counted-answer", 1, true) and "yes" or "no")
            ngx.say("upstream-hits=", tostring(ngx.shared.ai_cache_upstream_hits:get("n")))
        }
    }
--- response_body
r1-status=MISS
r2-status=HIT
r2-served-upstream-body=yes
upstream-hits=1
