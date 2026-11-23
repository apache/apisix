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
workers(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("request", "GET /t") unless $block->request;
    $block->set_value("no_error_log", "[error]\n[alert]") unless $block->error_log;
    my $upstream = <<'_EOC_';
    location /bucket_upstream {
        content_by_lua_block {
            local id = ngx.var.arg_hold
            if id then
                local signals = ngx.shared["plugin-limit-conn"]
                signals:set("held:" .. id, true, 20)
                local released
                for _ = 1, 1500 do
                    if signals:get("release:" .. id) then
                        released = true
                        break
                    end
                    ngx.sleep(0.01)
                end
                assert(released, "held request was not released")
            end
            ngx.say("ok")
        }
    }
_EOC_
    $block->set_value("config", $block->config . $upstream);
});

run_tests;

__DATA__

=== TEST 1: limit-count applies new thresholds to existing consumption and separates new scopes
--- config
    location /t {
        content_by_lua_block {
            for _, policy in ipairs({"local", "redis", "redis-cluster", "redis-sentinel"}) do
                local helper = require("lib.limit_bucket").new("limit-count")
                local conf = {count = 2, time_window = 60, policy = policy,
                              redis_host = "127.0.0.1", rejected_code = 429}
                helper:set(conf)
                assert(helper:hit().status == 200)
                assert(helper:hit().status == 200)
                conf.count = 4
                helper:set(conf)
                local res = helper:hit()
                assert(res.status == 200 and res.headers["X-RateLimit-Remaining"] == "1")
                conf.count = 2
                conf.rejected_msg = "kept"
                helper:set(conf)
                res = helper:hit()
                assert(res.status == 429 and res.body:find("kept", 1, true))
                conf.time_window = 120
                helper:set(conf)
                assert(helper:hit().headers["X-RateLimit-Remaining"] == "1")
                conf._meta = {filter = {{"request_method", "==", "GET"}}}
                helper:set(conf)
                assert(helper:hit().headers["X-RateLimit-Remaining"] == "1")
                conf.key_type = "constant"
                conf.key = "127.0.0.1"
                helper:set(conf)
                assert(helper:hit().headers["X-RateLimit-Remaining"] == "1")
                ngx.say(policy, ": passed")
            end
        }
    }
--- response_body
local: passed
redis: passed
redis-cluster: passed
redis-sentinel: passed
--- timeout: 20



=== TEST 2: limit-conn keeps open connections and releases old reservations after an update
--- config
    location /t {
        content_by_lua_block {
            for _, policy in ipairs({"local", "redis", "redis-cluster"}) do
                local helper = require("lib.limit_bucket").new("limit-conn")
                local conf = {conn = 2, burst = 0, default_conn_delay = 0.01,
                              key = "remote_addr", policy = policy,
                              redis_host = "127.0.0.1", rejected_code = 429}
                helper:set(conf)
                local release_old = helper:hold(2)
                conf.conn = 1
                helper:set(conf)
                assert(helper:hit().status == 429)
                conf.conn = 3
                helper:set(conf)
                local release_new = helper:hold(1)
                release_old()
                conf.conn = 1
                conf.rejected_msg = "kept"
                helper:set(conf)
                local res = helper:hit()
                assert(res.status == 429 and res.body:find("kept", 1, true))
                release_new()
                -- Redis releases run in a timer from log phase.
                for _ = 1, 100 do
                    if helper:hit().status == 200 then
                        ngx.say(policy, ": passed")
                        break
                    end
                    ngx.sleep(0.01)
                end
            end
        }
    }
--- response_body
local: passed
redis: passed
redis-cluster: passed
--- timeout: 20



=== TEST 3: limit-req keeps the current bucket when limits or rejection settings change
--- config
    location /t {
        content_by_lua_block {
            for _, policy in ipairs({"local", "redis", "redis-cluster"}) do
                local helper = require("lib.limit_bucket").new("limit-req")
                local conf = {rate = 0.01, burst = 1, nodelay = true,
                              key = "remote_addr", policy = policy,
                              redis_host = "127.0.0.1", rejected_code = 429}
                helper:set(conf)
                assert(helper:hit().status == 200)
                assert(helper:hit().status == 200)
                assert(helper:hit().status == 429)
                conf.rate = 0.02
                conf.rejected_msg = "kept"
                helper:set(conf)
                local res = helper:hit()
                assert(res.status == 429 and res.body:find("kept", 1, true))
                conf.burst = 2
                helper:set(conf)
                assert(helper:hit().status == 200)
                assert(helper:hit().status == 429)
                conf._meta = {filter = {{"request_method", "==", "GET"}}}
                helper:set(conf)
                assert(helper:hit().status == 200)
                ngx.say(policy, ": passed")
            end
        }
    }
--- response_body
local: passed
redis: passed
redis-cluster: passed
--- timeout: 20



=== TEST 4: a higher delayed-sync count is not overwritten by an old-limit snapshot
--- config
    location /t {
        content_by_lua_block {
            local helper = require("lib.limit_bucket").new("limit-count")
            local conf = {count = 2, time_window = 60, policy = "redis",
                          redis_host = "127.0.0.1", rejected_code = 429, sync_interval = 30}
            helper:set(conf)
            assert(helper:hit().status == 200)
            assert(helper:hit().status == 200)
            conf.count = 4
            helper:set(conf)
            local res = helper:hit()
            assert(res.status == 200 and res.headers["X-RateLimit-Remaining"] == "1")
            local old = require("apisix.plugins.limit-count.limit-count-redis").new(
                "plugin-limit-count", 2, 60, conf, "v1")
            local delay, remaining, reset, info = old:incoming(helper:key(), 2)
            assert(delay and remaining == 0)
            assert(old.delayed_syncer:sync_to_shm(helper:key(), remaining, reset, 2, info) == nil)
            res = helper:hit()
            assert(res.status == 200 and res.headers["X-RateLimit-Remaining"] == "0")
            assert(helper:hit().status == 429)
            ngx.say("passed")
        }
    }
--- response_body
passed
--- timeout: 15



=== TEST 5: a credential rotation keeps pending delayed-sync consumption
--- config
    location /t {
        content_by_lua_block {
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            assert(red:acl("SETUSER", "bucket-test", "on", ">bucket-password", "~*", "+@all"))
            local helper = require("lib.limit_bucket").new("limit-count")
            local conf = {count = 2, time_window = 60, policy = "redis", sync_interval = 1,
                          redis_host = "127.0.0.1", rejected_code = 429}
            helper:set(conf)
            assert(helper:hit().status == 200)
            assert(helper:hit().status == 200)
            conf.redis_username = "bucket-test"
            conf.redis_password = "bucket-password"
            helper:set(conf)
            assert(helper:hit().status == 429)
            ngx.say("passed")
        }
    }
--- response_body
passed
--- timeout: 15



=== TEST 6: changing a Redis database leaves pending consumption on its original backend
--- config
    location /t {
        content_by_lua_block {
            local helper = require("lib.limit_bucket").new("limit-count")
            local conf = {count = 2, time_window = 60, policy = "redis", sync_interval = 0.5,
                          redis_host = "127.0.0.1", redis_database = 14, rejected_code = 429}
            helper:set(conf)
            local old_key = "plugin-limit-count:v1:" .. helper:key()
            assert(helper:hit().status == 200)
            assert(helper:hit().status == 200)
            conf.redis_database = 15
            helper:set(conf)
            local new_key = "plugin-limit-count:v1:" .. helper:key()
            assert(helper:hit().status == 200)
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local matched
            for _ = 1, 200 do
                assert(red:select(14))
                local old = red:get(old_key)
                assert(red:select(15))
                local new = red:get(new_key)
                if old == "2" and new == "1" then
                    matched = true
                    break
                end
                ngx.sleep(0.01)
            end
            assert(matched, "pending usage moved to the wrong database")
            ngx.say("passed")
        }
    }
--- response_body
passed
--- timeout: 15



=== TEST 7: raising a sliding-window count recomputes the previous window's contribution
--- config
    location /t {
        content_by_lua_block {
            local helper = require("lib.limit_bucket").new("limit-count")
            -- A long window keeps both samples away from a window boundary.
            local window = 1000000000
            local conf = {count = 2, time_window = window, window_type = "sliding",
                          policy = "redis", redis_host = "127.0.0.1",
                          rejected_code = 429, sync_interval = 30}
            helper:set(conf)
            local red = require("resty.redis").new()
            assert(red:connect("127.0.0.1", 6379))
            local wid = math.floor(ngx.now() / window)
            local prefix = "plugin-limit-count:" .. helper:key() .. "."
            assert(red:setex(prefix .. (wid - 1) .. ".counter", window * 2, 8))
            assert(red:setex(prefix .. wid .. ".counter", window * 2, 1))
            assert(helper:hit().status == 429)
            conf.count = 10
            helper:set(conf)
            local res = helper:hit()
            assert(res.status == 200)
            local direct = require("apisix.plugins.limit-count.limit-count-redis").new(
                "plugin-limit-count", 10, window, conf, "v1")
            local delay, remaining = direct:incoming(helper:key(), 0)
            assert(delay)
            -- One newly admitted request is still pending locally.
            assert(tonumber(res.headers["X-RateLimit-Remaining"]) == remaining - 1)
            ngx.say("passed")
        }
    }
--- response_body
passed
--- timeout: 15



=== TEST 8: raising a fixed-window count preserves over-limit consumption in an old snapshot
--- config
    location /t {
        content_by_lua_block {
            local helper = require("lib.limit_bucket").new("limit-count")
            local conf = {count = 2, time_window = 60, policy = "redis", sync_interval = 30,
                          redis_host = "127.0.0.1", rejected_code = 429}
            helper:set(conf)
            local old = require("apisix.plugins.limit-count.limit-count-redis").new(
                "plugin-limit-count", 2, 60, helper.conf, "v1")
            local _, err, reset, info = old:incoming(helper:key(), 4)
            assert(err == "rejected" and info.count == 4)
            assert(old.delayed_syncer:sync_to_shm(helper:key(), 0, reset, 0, info) == nil)
            conf.count = 5
            helper:set(conf)
            local res = helper:hit()
            assert(res.status == 200 and res.headers["X-RateLimit-Remaining"] == "0")
            assert(helper:hit().status == 429)
            ngx.say("passed")
        }
    }
--- response_body
passed
--- timeout: 15



=== TEST 9: a sliding-window threshold update keeps pending usage local and counts it once
--- config
    location /t {
        content_by_lua_block {
            local helper = require("lib.limit_bucket").new("limit-count")
            local conf = {count = 2, time_window = 1000000000, window_type = "sliding",
                          policy = "redis", redis_host = "127.0.0.1",
                          rejected_code = 429, sync_interval = 30}
            helper:set(conf)
            assert(helper:hit().status == 200)
            assert(helper:hit().status == 200)
            conf.count = 3
            helper:set(conf)

            local redis = require("resty.redis")
            local old_get, old_evalsha, old_eval = redis.get, redis.evalsha, redis.eval
            local prefix = "plugin-limit-count:" .. helper:key() .. "."
            local calls = 0
            local function track(key)
                if type(key) == "string" and key:find(prefix, 1, true) == 1 then
                    calls = calls + 1
                end
            end
            redis.get = function(self, key)
                track(key)
                return old_get(self, key)
            end
            redis.evalsha = function(self, sha, nkeys, key, ...)
                track(key)
                return old_evalsha(self, sha, nkeys, key, ...)
            end
            redis.eval = function(self, script, nkeys, key, ...)
                track(key)
                return old_eval(self, script, nkeys, key, ...)
            end
            local res = helper:hit()
            redis.get, redis.evalsha, redis.eval = old_get, old_evalsha, old_eval
            assert(res.status == 200 and res.headers["X-RateLimit-Remaining"] == "0")
            assert(calls == 0, "a threshold update refreshed Redis on a cache hit")
            assert(helper:hit().status == 429)
            ngx.say("passed")
        }
    }
--- response_body
passed
--- timeout: 15
