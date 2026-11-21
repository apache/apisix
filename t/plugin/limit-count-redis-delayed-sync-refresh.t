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

run_tests();

__DATA__

=== TEST 1: refreshing remote quota counts a pending delta only once
--- timeout: 10
--- config
    location /t {
        content_by_lua_block {
            local limit_count = require("apisix.plugins.limit-count.limit-count-redis")
            local cjson = require("cjson.safe")
            local red = require("resty.redis"):new()
            assert(red:connect("127.0.0.1", 6379))

            local window = 60
            -- Keep the Redis sliding window stable while forcing only the cached quota to expire.
            local until_reset = window - ngx.now() % window
            if until_reset < 5 then
                ngx.sleep(until_reset + 0.01)
            end

            for _, window_type in ipairs({"fixed", "sliding"}) do
                for _, cache_state in ipairs({"expired", "missing"}) do
                    local conf = {
                        redis_host = "127.0.0.1",
                        redis_port = 6379,
                        redis_database = 0,
                        window_type = window_type,
                        sync_interval = 30,
                    }
                    local lim = assert(limit_count.new("plugin-limit-count", 2, window, conf))
                    local syncer = lim.delayed_syncer
                    local shd = syncer.shd
                    local key = ":quota-refresh-" .. window_type .. "-" .. cache_state
                                .. "-" .. ngx.worker.pid()
                    local syncer_id = key
                    local delta_key = syncer:key_local_delta(key)
                    local quota_key = syncer:key_remote_quota(key)
                    local timer_key = syncer:key_sync_timer(syncer_id)

                    assert(shd:set(delta_key, 1, 2 * window))
                    if cache_state == "expired" then
                        assert(shd:set(quota_key, assert(cjson.encode({
                            remaining = 2,
                            reset = 1,
                            sync_at = ngx.now() - 2,
                        })), 2 * window))
                    end
                    -- Reserve the timer slot and drain the real queue explicitly below.
                    assert(shd:set(timer_key, ngx.now() + conf.sync_interval))

                    ngx.say(window_type, " ", cache_state)
                    local delay, remaining = lim:incoming_delayed(key, 1, syncer_id)
                    ngx.say("first: ", delay, ", ", remaining)
                    ngx.say("pending: ", shd:get(delta_key))

                    local function redis_count()
                        local prefix = "plugin-limit-count"
                        if window_type == "sliding" then
                            prefix = prefix .. ":"
                        end
                        local keys = assert(red:keys(prefix .. key .. "*"))
                        local count = 0
                        for _, counter_key in ipairs(keys) do
                            count = count + tonumber(assert(red:get(counter_key)))
                        end
                        return count, keys
                    end

                    local count = redis_count()
                    ngx.say("committed: ", count)
                    delay, remaining = lim:incoming_delayed(key, 1, syncer_id)
                    ngx.say("next: ", delay, ", ", remaining)

                    syncer:sync(syncer_id, ngx.now())
                    local keys
                    count, keys = redis_count()
                    ngx.say("after sync: ", count, ", pending: ", shd:get(delta_key))

                    for _, counter_key in ipairs(keys) do
                        assert(red:del(counter_key))
                    end
                    shd:delete(delta_key)
                    shd:delete(quota_key)
                    shd:delete(timer_key)
                end
            end
            assert(red:close())
        }
    }
--- request
GET /t
--- response_body
fixed expired
first: 0, 0
pending: 1
committed: 1
next: nil, rejected
after sync: 2, pending: 0
fixed missing
first: 0, 0
pending: 1
committed: 1
next: nil, rejected
after sync: 2, pending: 0
sliding expired
first: 0, 0
pending: 1
committed: 1
next: nil, rejected
after sync: 2, pending: 0
sliding missing
first: 0, 0
pending: 1
committed: 1
next: nil, rejected
after sync: 2, pending: 0
--- no_error_log
[error]
[alert]
