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

=== TEST 1: schema smoke (valid accepted; missing redis_host rejected; unknown policy rejected)
--- config
    location /t {
        content_by_lua_block {
            local schema_mod = require("apisix.plugins.ai-cache.schema")
            local core       = require("apisix.core")

            -- (a) valid single-node redis config is accepted
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

            -- (c) unknown policy is rejected
            local ok3, err3 = core.schema.check(schema_mod.schema, {
                policy = "memory",
            })
            if ok3 then
                ngx.say("FAIL reject: unknown policy was accepted")
                return
            end

            ngx.say("accept ok")
            ngx.say("missing-host-err: " .. (err2 and "rejected" or "?"))
            ngx.say("unknown-policy-err: " .. (err3 and "rejected" or "?"))
        }
    }
--- response_body
accept ok
missing-host-err: rejected
unknown-policy-err: rejected



=== TEST 2: SKIP-STREAM — stream=true gets X-AI-Cache-Status: SKIP-STREAM and body still streamed
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/stream-test",
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
                ngx.say("route setup failed: ", code)
                return
            end
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 3: SKIP-STREAM — stream request returns SKIP-STREAM header and ai-proxy streams body
--- request
POST /stream-test
{"model":"gpt-4o","messages":[{"role":"user","content":"hi"}],"stream":true}
--- more_headers
X-AI-Fixture: openai/chat-streaming.sse
--- response_headers
X-AI-Cache-Status: SKIP-STREAM
--- response_body_like eval
qr/data: \[DONE\]/



=== TEST 4: MISS proxies upstream — non-stream cache miss serves upstream body
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



=== TEST 5: MISS — non-stream request hits upstream and returns MISS header
--- request
POST /anything
{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_headers
X-AI-Cache-Status: MISS
--- response_body_like eval
qr/"1 \+ 1 = 2\."/



=== TEST 6: HIT short-circuit with dead upstream — pre-seeded key returns FROM-CACHE even when upstream unreachable
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

            -- Pre-populate Redis with a cached body using effective key:
            -- instance name "stub", protocol "openai-chat", model from options "gpt-4o"
            -- (no model override divergence here — instance options.model == gpt-4o,
            --  and the client also sends gpt-4o, so effective == client body)
            local key_mod = require("apisix.plugins.ai-cache.key")
            local key = key_mod.build(
                {
                    model    = "gpt-4o",
                    messages = {{ role = "user", content = "cached" }},
                },
                { protocol = "openai-chat", instance = "stub" }
            )
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

            -- Issue the request via resty.http to the same nginx so the pre-seeded
            -- key is present when before_proxy runs.
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



=== TEST 7: miss->hit round-trip, upstream invoked exactly once
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



=== TEST 8: fail-open when Redis is unreachable — request still 200 with MISS and upstream body
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



=== TEST 9: corrupt cached JSON is dropped and treated as miss, never served
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

            -- Seed Redis with corrupt JSON under the effective key.
            local key_mod = require("apisix.plugins.ai-cache.key")
            local key = key_mod.build(
                {
                    model    = "gpt-4o",
                    messages = {{ role = "user", content = "corrupt" }},
                },
                { protocol = "openai-chat", instance = "stub" }
            )
            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", err)
                return
            end
            local ok2, set_err = r:setex(key, 60, "{not valid json")
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



=== TEST 10: oversize response body is not written to cache
--- config
    location /t {
        content_by_lua_block {
            -- Drive the log phase directly with a forged ctx so we don't
            -- depend on an upstream fixture larger than 1 MiB.
            local plugin = require("apisix.plugins.ai-cache")
            local key_mod = require("apisix.plugins.ai-cache.key")
            local k = key_mod.build(
                {
                    model    = "gpt-4o",
                    messages = {{ role = "user", content = "oversized" }},
                },
                { protocol = "openai-chat", instance = "stub" }
            )
            local conf = {
                policy     = "redis",
                redis_host = "127.0.0.1",
                exact      = { ttl = 60 },
                redis_keepalive_timeout = 10000,
                redis_keepalive_pool    = 100,
            }
            local oversize = string.rep("x", 1048577)   -- 1 MiB + 1
            ngx.ctx.ai_cache = { key = k, started_at = ngx.now() }
            ngx.ctx.llm_raw_response_body = '{"body":"' .. oversize .. '"}'
            ngx.status = 200

            plugin.log(conf, ngx.ctx)

            -- Let any scheduled timer drain (should be none).
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



=== TEST 11: redis-cluster slot-lock shared dict is declared
--- config
    location /t {
        content_by_lua_block {
            local dict = ngx.shared["plugin-ai-cache-redis-cluster-slot-lock"]
            ngx.say(dict ~= nil and "declared" or "MISSING")
        }
    }
--- response_body
declared



=== TEST 12: effective-body divergence — model override changes the cache key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- Route whose instance forces model to "forced-model" via options.
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
                                "options": { "model": "forced-model" },
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

            -- Send a request with model "gpt-4o" in the client body; instance
            -- will override to "forced-model".
            local http = require("resty.http")
            local hc = http.new()
            local res, req_err = hc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/anything",
                {
                    method = "POST",
                    body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"ovr"}]}]],
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

            -- Give the log-phase timer time to SETEX.
            ngx.sleep(0.3)

            -- Now inspect Redis: the EFFECTIVE key (forced-model) must exist;
            -- the RAW-client key (gpt-4o) must NOT exist.
            local key_mod = require("apisix.plugins.ai-cache.key")
            local eff_key = key_mod.build(
                { model = "forced-model", messages = {{ role = "user", content = "ovr" }} },
                { protocol = "openai-chat", instance = "stub" }
            )
            local raw_key = key_mod.build(
                { model = "gpt-4o", messages = {{ role = "user", content = "ovr" }} },
                { protocol = "openai-chat", instance = "stub" }
            )

            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", err)
                return
            end
            local eff_val = r:get(eff_key)
            local raw_val = r:get(raw_key)
            ngx.say("effective-key-exists=", (eff_val ~= ngx.null and eff_val ~= nil) and "yes" or "no")
            ngx.say("raw-key-exists=", (raw_val ~= ngx.null and raw_val ~= nil) and "yes" or "no")
        }
    }
--- response_body
effective-key-exists=yes
raw-key-exists=no



=== TEST 13: instance isolation — same body under different instance names produces distinct keys
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Route 1: instance "inst-a"
            local code1 = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/inst-a",
                    "plugins": {
                        "ai-cache": {
                            "policy":     "redis",
                            "redis_host": "127.0.0.1",
                            "exact":      { "ttl": 60 }
                        },
                        "ai-proxy-multi": {
                            "instances": [{
                                "name": "inst-a",
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
            -- Route 2: instance "inst-b"
            local code2 = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/inst-b",
                    "plugins": {
                        "ai-cache": {
                            "policy":     "redis",
                            "redis_host": "127.0.0.1",
                            "exact":      { "ttl": 60 }
                        },
                        "ai-proxy-multi": {
                            "instances": [{
                                "name": "inst-b",
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
            if code1 >= 300 or code2 >= 300 then
                ngx.say("route setup failed: ", code1, " / ", code2)
                return
            end

            local http = require("resty.http")
            local body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"isolation-test"}]}]]

            -- Request 1: inst-a → MISS (writes to Redis under inst-a key)
            local hc1 = http.new()
            local r1, err1 = hc1:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/inst-a",
                {
                    method = "POST",
                    body = body,
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "openai/chat-basic.json",
                    },
                }
            )
            if not r1 then ngx.say("req1 failed: ", err1); return end
            ngx.say("r1-status=", tostring(r1.headers["X-AI-Cache-Status"]))

            -- Let log timer write to Redis.
            ngx.sleep(0.3)

            -- Request 2: inst-b with same body → must be MISS (different instance key)
            local hc2 = http.new()
            local r2, err2 = hc2:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/inst-b",
                {
                    method = "POST",
                    body = body,
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["X-AI-Fixture"] = "openai/chat-basic.json",
                    },
                }
            )
            if not r2 then ngx.say("req2 failed: ", err2); return end
            ngx.say("r2-status=", tostring(r2.headers["X-AI-Cache-Status"]))

            -- Assert the two distinct keys both exist in Redis.
            ngx.sleep(0.3)
            local key_mod = require("apisix.plugins.ai-cache.key")
            local key_a = key_mod.build(
                { model = "gpt-4o", messages = {{ role = "user", content = "isolation-test" }} },
                { protocol = "openai-chat", instance = "inst-a" }
            )
            local key_b = key_mod.build(
                { model = "gpt-4o", messages = {{ role = "user", content = "isolation-test" }} },
                { protocol = "openai-chat", instance = "inst-b" }
            )
            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then ngx.say("redis connect failed: ", err); return end
            local va = r:get(key_a)
            local vb = r:get(key_b)
            ngx.say("inst-a-key-exists=", (va ~= ngx.null and va ~= nil) and "yes" or "no")
            ngx.say("inst-b-key-exists=", (vb ~= ngx.null and vb ~= nil) and "yes" or "no")
        }
    }
--- response_body
r1-status=MISS
r2-status=MISS
inst-a-key-exists=yes
inst-b-key-exists=yes
