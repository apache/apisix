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
  - ai-proxy
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



=== TEST 2: SKIP-STREAM route setup (ai-proxy + ai-cache)
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
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer x" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" },
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



=== TEST 4: miss->hit round-trip — MISS then HIT, upstream invoked exactly once
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
            -- Under TEST_NGINX_USE_HUP=1 the shared dict survives reloads
            -- across blocks; start this block's count from zero.
            ngx.shared.ai_cache_upstream_hits:set("n", 0)

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
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer x" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1986" },
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



=== TEST 5: HIT serves the cached bytes, not the upstream — overwrite the stored entry, see the marker
--- http_config
    lua_shared_dict ai_cache_upstream_hits 1m;
    server {
        listen 1986;
        location / {
            content_by_lua_block {
                ngx.shared.ai_cache_upstream_hits:incr("n", 1, 0)
                ngx.header["Content-Type"] = "application/json"
                ngx.print('{"id":"live-1","object":"chat.completion","model":"gpt-4o",'
                    .. '"choices":[{"index":0,"message":{"role":"assistant","content":"live-answer"},'
                    .. '"finish_reason":"stop"}]}')
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            -- Under TEST_NGINX_USE_HUP=1 the shared dict survives the reload
            -- from the previous block; start this block's count from zero.
            ngx.shared.ai_cache_upstream_hits:set("n", 0)

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
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer x" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1986" },
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
            local body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"cached"}]}]]
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

            -- Prime the cache, then discover the key the plugin computed.
            -- (The key is scoped by the route's conf_version, so the test
            -- can't precompute it — and a route edit would, by design,
            -- invalidate the entry.)
            local r1 = send()
            if not r1 then ngx.say("req1 failed"); return end
            ngx.say("r1-status=", tostring(r1.headers["X-AI-Cache-Status"]))
            ngx.sleep(0.3)

            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", err)
                return
            end
            local keys = r:keys("ai-cache:l1:*")
            if not keys or #keys ~= 1 then
                ngx.say("unexpected key count: ", keys and #keys or "nil")
                return
            end
            local cached_body = '{"choices":[{"message":{"role":"assistant","content":"FROM-CACHE"}}],"id":"cached-1","model":"gpt-4o","object":"chat.completion"}'
            local ok2, set_err = r:setex(keys[1], 60, cached_body)
            if not ok2 then
                ngx.say("redis setex failed: ", set_err)
                return
            end

            local r2 = send()
            if not r2 then ngx.say("req2 failed"); return end
            ngx.say("r2-status=", tostring(r2.headers["X-AI-Cache-Status"]))
            ngx.say("content-type=", tostring(r2.headers["Content-Type"]))
            ngx.say("body-has-cache-marker=",
                    string.find(r2.body, "FROM-CACHE", 1, true) and "yes" or "no")
            ngx.say("upstream-hits=", tostring(ngx.shared.ai_cache_upstream_hits:get("n")))
        }
    }
--- response_body
r1-status=MISS
r2-status=HIT
content-type=application/json
body-has-cache-marker=yes
upstream-hits=1



=== TEST 6: config-edit invalidation — re-saving the route makes the next request a MISS
--- http_config
    lua_shared_dict ai_cache_upstream_hits 1m;
    server {
        listen 1986;
        location / {
            content_by_lua_block {
                ngx.shared.ai_cache_upstream_hits:incr("n", 1, 0)
                ngx.header["Content-Type"] = "application/json"
                ngx.print('{"id":"inv-1","object":"chat.completion","model":"gpt-4o",'
                    .. '"choices":[{"index":0,"message":{"role":"assistant","content":"answer"},'
                    .. '"finish_reason":"stop"}]}')
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local route = [[{
                "uri": "/anything",
                "plugins": {
                    "ai-cache": {
                        "policy":     "redis",
                        "redis_host": "127.0.0.1",
                        "exact":      { "ttl": 60 }
                    },
                    "ai-proxy": {
                        "provider": "openai",
                        "auth": { "header": { "Authorization": "Bearer x" } },
                        "options": { "model": "gpt-4o" },
                        "override": { "endpoint": "http://127.0.0.1:1986" },
                        "ssl_verify": false
                    }
                }
            }]]
            local code = t('/apisix/admin/routes/1', ngx.HTTP_PUT, route)
            if code >= 300 then
                ngx.say("route setup failed: ", code)
                return
            end

            local http = require("resty.http")
            local body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"invalidation"}]}]]
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
            ngx.sleep(0.3)

            local r2 = send()
            if not r2 then ngx.say("req2 failed"); return end
            ngx.say("r2-status=", tostring(r2.headers["X-AI-Cache-Status"]))

            -- Re-save the identical route: etcd bumps modifiedIndex, so
            -- conf_version changes and the old entry must become unreachable.
            -- (The same mechanism covers real edits, e.g. an ai-proxy
            -- options.model override change.)
            local code2 = t('/apisix/admin/routes/1', ngx.HTTP_PUT, route)
            if code2 >= 300 then
                ngx.say("route re-save failed: ", code2)
                return
            end
            ngx.sleep(0.5)

            local r3 = send()
            if not r3 then ngx.say("req3 failed"); return end
            ngx.say("r3-status=", tostring(r3.headers["X-AI-Cache-Status"]))
        }
    }
--- response_body
r1-status=MISS
r2-status=HIT
r3-status=MISS



=== TEST 7: fail-open when Redis is unreachable — request still 200 with MISS and upstream body
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
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer x" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" },
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



=== TEST 8: corrupt cached JSON is dropped and treated as miss, never served
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
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": { "header": { "Authorization": "Bearer x" } },
                            "options": { "model": "gpt-4o" },
                            "override": { "endpoint": "http://127.0.0.1:1980" },
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
            local body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"corrupt"}]}]]
            local function send()
                local hc = http.new()
                return hc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/anything",
                    {
                        method = "POST",
                        body = body,
                        headers = {
                            ["Content-Type"] = "application/json",
                            ["X-AI-Fixture"] = "openai/chat-basic.json",
                        },
                    }
                )
            end

            -- Prime the cache so the key exists, then corrupt the entry.
            local r1 = send()
            if not r1 then ngx.say("req1 failed"); return end
            ngx.sleep(0.3)

            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", err)
                return
            end
            local keys = r:keys("ai-cache:l1:*")
            if not keys or #keys ~= 1 then
                ngx.say("unexpected key count: ", keys and #keys or "nil")
                return
            end
            local key = keys[1]
            local ok2, set_err = r:setex(key, 60, "{not valid json")
            if not ok2 then
                ngx.say("redis setex failed: ", set_err)
                return
            end

            local res = send()
            if not res then
                ngx.say("request failed")
                return
            end
            ngx.say("status=", res.status)
            ngx.say("cache-status=", tostring(res.headers["X-AI-Cache-Status"]))
            ngx.say("served-corrupt=",
                    string.find(res.body, "not valid json", 1, true) and "yes" or "no")
            ngx.say("served-upstream=",
                    string.find(res.body, "1 %+ 1 = 2", 1, false) and "yes" or "no")

            -- The corrupt entry must have been deleted on read.
            local v = r:get(key)
            ngx.say("corrupt-entry-deleted=",
                    (v == ngx.null or string.find(v or "", "not valid json", 1, true) == nil)
                    and "yes" or "no")
        }
    }
--- response_body
status=200
cache-status=MISS
served-corrupt=no
served-upstream=yes
corrupt-entry-deleted=yes
--- error_log
ai-cache: corrupt cached



=== TEST 9: ai-proxy-multi routes bypass caching (no cache header, nothing written)
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
                    body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"multi-bypass"}]}]],
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
            ngx.say("cache-header-absent=",
                    res.headers["X-AI-Cache-Status"] == nil and "yes" or "no")

            ngx.sleep(0.3)
            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", err)
                return
            end
            local keys = r:keys("ai-cache:l1:*")
            ngx.say("nothing-written=", (keys and #keys == 0) and "yes" or "no")
        }
    }
--- response_body
status=200
cache-header-absent=yes
nothing-written=yes



=== TEST 10: ai-proxy-multi attached via a service also bypasses caching (merged-conf check)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code1 = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
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
            local code2 = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/anything",
                    "service_id": "1",
                    "plugins": {
                        "ai-cache": {
                            "policy":     "redis",
                            "redis_host": "127.0.0.1"
                        }
                    }
                }]]
            )
            if code1 >= 300 or code2 >= 300 then
                ngx.say("setup failed: ", code1, " / ", code2)
                return
            end
            ngx.sleep(0.5)

            local http = require("resty.http")
            local hc = http.new()
            local res, req_err = hc:request_uri(
                "http://127.0.0.1:" .. ngx.var.server_port .. "/anything",
                {
                    method = "POST",
                    body = [[{"model":"gpt-4o","messages":[{"role":"user","content":"svc-multi-bypass"}]}]],
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
            ngx.say("cache-header-absent=",
                    res.headers["X-AI-Cache-Status"] == nil and "yes" or "no")

            ngx.sleep(0.3)
            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("redis connect failed: ", err)
                return
            end
            local keys = r:keys("ai-cache:l1:*")
            ngx.say("nothing-written=", (keys and #keys == 0) and "yes" or "no")
        }
    }
--- response_body
status=200
cache-header-absent=yes
nothing-written=yes



=== TEST 11: oversize response body is not written to cache
--- config
    location /t {
        content_by_lua_block {
            -- Drive the log phase directly with a forged ctx so we don't
            -- depend on an upstream fixture larger than 1 MiB.
            local plugin = require("apisix.plugins.ai-cache")
            local key_mod = require("apisix.plugins.ai-cache.key")
            local k = key_mod.build(
                { model = "gpt-4o", messages = {{ role = "user", content = "oversized" }} },
                { conf_id = "1", conf_version = 1 }
            )
            local conf = {
                policy     = "redis",
                redis_host = "127.0.0.1",
                exact      = { ttl = 60 },
                redis_keepalive_timeout = 10000,
                redis_keepalive_pool    = 100,
            }
            local oversize = string.rep("x", 1048577)   -- 1 MiB + 1
            ngx.ctx.ai_cache = {
                key  = k,
                body = '{"body":"' .. oversize .. '"}',
            }
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



=== TEST 12: non-2xx upstream response is not written to cache
--- config
    location /t {
        content_by_lua_block {
            -- Drive the log phase directly with a forged ctx and a non-2xx
            -- status; the status guard must refuse to cache the error body so
            -- a later identical request is not served a stale error as a 200.
            local plugin = require("apisix.plugins.ai-cache")
            local key_mod = require("apisix.plugins.ai-cache.key")
            local k = key_mod.build(
                { model = "gpt-4o", messages = {{ role = "user", content = "error-not-cached" }} },
                { conf_id = "1", conf_version = 1 }
            )
            local conf = {
                policy     = "redis",
                redis_host = "127.0.0.1",
                exact      = { ttl = 60 },
                redis_keepalive_timeout = 10000,
                redis_keepalive_pool    = 100,
            }
            ngx.ctx.ai_cache = {
                key  = k,
                -- Valid JSON body, but the upstream failed.
                body = '{"error":{"message":"upstream is down"}}',
            }

            -- Drive the log phase as if the upstream returned 502, then restore
            -- the status so this test endpoint still responds 200 to the harness.
            ngx.status = 502
            plugin.log(conf, ngx.ctx)
            ngx.status = 200

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
            ngx.say(v == ngx.null and "not-written" or "WRITTEN")
        }
    }
--- response_body
not-written



=== TEST 13: non-JSON upstream body is not written to cache
--- config
    location /t {
        content_by_lua_block {
            -- Forge a 2xx response whose body is not JSON; the write-side JSON
            -- guard must refuse it so a later request is not served garbage
            -- under a forced application/json content type.
            local plugin = require("apisix.plugins.ai-cache")
            local key_mod = require("apisix.plugins.ai-cache.key")
            local k = key_mod.build(
                { model = "gpt-4o", messages = {{ role = "user", content = "non-json" }} },
                { conf_id = "1", conf_version = 1 }
            )
            local conf = {
                policy     = "redis",
                redis_host = "127.0.0.1",
                exact      = { ttl = 60 },
                redis_keepalive_timeout = 10000,
                redis_keepalive_pool    = 100,
            }
            ngx.ctx.ai_cache = {
                key  = k,
                body = "this is not json at all",
            }
            ngx.status = 200

            plugin.log(conf, ngx.ctx)
            ngx.sleep(0.1)

            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("connect failed: ", err)
                return
            end
            ngx.say(r:get(k) == ngx.null and "not-written" or "WRITTEN")
        }
    }
--- response_body
not-written



=== TEST 14: a successful write applies the configured TTL (not the schema default)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local key_mod = require("apisix.plugins.ai-cache.key")
            local k = key_mod.build(
                { model = "gpt-4o", messages = {{ role = "user", content = "ttl-check" }} },
                { conf_id = "1", conf_version = 1 }
            )
            local conf = {
                policy     = "redis",
                redis_host = "127.0.0.1",
                redis_database = 0,
                exact      = { ttl = 55 },
                redis_keepalive_timeout = 10000,
                redis_keepalive_pool    = 100,
            }
            ngx.ctx.ai_cache = {
                key  = k,
                body = '{"id":"x","object":"chat.completion","choices":[]}',
            }
            ngx.status = 200

            plugin.log(conf, ngx.ctx)
            ngx.sleep(0.2)

            local r = require("resty.redis").new()
            r:set_timeouts(1000, 1000, 1000)
            local ok, err = r:connect("127.0.0.1", 6379)
            if not ok then
                ngx.say("connect failed: ", err)
                return
            end
            local ttl = r:ttl(k)
            ngx.say("written=", (r:get(k) ~= ngx.null) and "yes" or "no")
            -- TTL must reflect the configured 55s, well below the 3600 default.
            ngx.say("ttl-in-range=",
                    (type(ttl) == "number" and ttl > 0 and ttl <= 55) and "yes" or "no")
        }
    }
--- response_body
written=yes
ttl-in-range=yes
