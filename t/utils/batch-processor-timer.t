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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: a full manager recovers after batch timers are dropped
--- http_config
    lua_max_running_timers 16;
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")
            plugin.plugin_metadatas = {
                get = function()
                    return {value = {max_pending_entries = 8}}
                end
            }
            local manager = require("apisix.utils.batch-processor-manager").new("recovery")
            local conf = {name = "recovery", batch_max_size = 1}
            local ctx = {var = {route_id = "1", server_addr = "127.0.0.1"}}
            local sent = 0
            local function send(entries)
                sent = sent + #entries
                return true
            end
            local function push(entry)
                if not manager:add_entry(conf, entry) then
                    manager:add_entry_to_new_processor(conf, entry, ctx, send)
                end
            end

            local pressure = true
            for attempt = 1, 20 do
                for i = 1, 16 - ngx.timer.running_count() do
                    assert(ngx.timer.at(0, function(premature)
                        while pressure and not premature and not ngx.worker.exiting() do
                            ngx.sleep(0.01)
                        end
                    end))
                end
                ngx.sleep(0.01)
                if ngx.timer.running_count() == 16 then
                    break
                end
            end
            assert(ngx.timer.running_count() == 16)
            for i = 1, 8 do
                push(i)
            end
            -- Also drop the first recovery tick, not only the process timers.
            ngx.sleep(1.2)
            pressure = false
            assert(sent < 8, "timer pressure must have dropped a batch")
            ngx.sleep(2.1)
            local before = sent
            push("after recovery")
            ngx.sleep(0.1)
            assert(sent == before + 1, "the logger must resume without a reload")
            assert(manager.total_pushed_entries == 9)
            local processed = 0
            for _, processor in pairs(manager.buffers) do
                processed = processed + processor.processed_entries
            end
            assert(processed == 9, "dropped batches must release the backlog exactly once")
            ngx.say("recovered")
        }
    }
--- request
GET /t
--- response_body
recovered
--- error_log
lua_max_running_timers are not enough
entries whose process timers did not start
--- timeout: 10



=== TEST 2: a dropped buffer timer flushes without another entry
--- http_config
    lua_max_running_timers 16;
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local sent = 0
            local processor = assert(Batch:new(function(entries)
                sent = sent + #entries
                return true
            end, {name = "buffer recovery", batch_max_size = 10, inactive_timeout = 1}))

            local pressure = true
            for attempt = 1, 20 do
                for i = 1, 16 - ngx.timer.running_count() do
                    assert(ngx.timer.at(0, function(premature)
                        while pressure and not premature and not ngx.worker.exiting() do
                            ngx.sleep(0.01)
                        end
                    end))
                end
                ngx.sleep(0.01)
                if ngx.timer.running_count() == 16 then
                    break
                end
            end
            assert(ngx.timer.running_count() == 16)
            processor:push("buffered")
            ngx.sleep(1.2)
            pressure = false
            assert(sent == 0, "the buffer timer must have been dropped")
            ngx.sleep(2.1)
            assert(sent == 1)
            assert(processor.processed_entries == 1)
            assert(not processor.is_timer_running)
            ngx.say("flushed")
        }
    }
--- request
GET /t
--- response_body
flushed
--- error_log
lua_max_running_timers are not enough
recovering buffer timer
--- timeout: 10



=== TEST 3: a running slow callback is not reclaimed
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local started, sent = 0, 0
            local processor = assert(Batch:new(function(entries)
                started = started + 1
                ngx.sleep(3)
                sent = sent + #entries
                return true
            end, {name = "slow callback", batch_max_size = 1}))
            processor:push("slow")
            ngx.sleep(2.2)
            assert(started == 1)
            assert(processor.processed_entries == 0, "a running callback is still pending")
            ngx.sleep(1)
            assert(sent == 1)
            assert(processor.processed_entries == 1)
            ngx.say("sent once")
        }
    }
--- request
GET /t
--- response_body
sent once
--- no_error_log
[error]
--- timeout: 10



=== TEST 4: a delayed partial retry is not reclaimed before it is due
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local calls = 0
            local processor = assert(Batch:new(function(entries)
                calls = calls + 1
                if calls == 1 then
                    assert(#entries == 3)
                    return false, "partial failure", 2
                end
                assert(#entries == 2)
                return true
            end, {name = "delayed retry", batch_max_size = 3,
                  max_retry_count = 1, retry_delay = 3}))
            processor:push("a")
            processor:push("b")
            processor:push("c")
            ngx.sleep(2.2)
            assert(calls == 1)
            assert(processor.processed_entries == 1)
            ngx.sleep(1)
            assert(calls == 2)
            assert(processor.processed_entries == 3)
            ngx.say("retried once")
        }
    }
--- request
GET /t
--- response_body
retried once
--- error_log
failed to process entries [2/3]: partial failure
--- no_error_log
entries whose process timers did not start
--- timeout: 10



=== TEST 5: an overdue callback cannot send or settle the same batch twice
--- config
    location /t {
        content_by_lua_block {
            local timer_at = ngx.timer.at
            local callback, owner, batch
            ngx.timer.at = function(delay, func, self, entries)
                callback, owner, batch = func, self, entries
                return true
            end
            package.loaded["apisix.utils.batch-processor"] = nil
            local Batch = require("apisix.utils.batch-processor")
            ngx.timer.at = timer_at
            local sent = 0
            local processor = assert(Batch:new(function(entries)
                sent = sent + #entries
                return true
            end, {name = "late callback", batch_max_size = 1}))
            processor:push("overdue")
            ngx.sleep(2.2)
            assert(processor.processed_entries == 1)
            callback(false, owner, batch)
            assert(sent == 0)
            assert(processor.processed_entries == 1)
            ngx.say("settled once")
        }
    }
--- request
GET /t
--- response_body
settled once
--- error_log
dropping 1 entries whose process timers did not start
--- timeout: 10



=== TEST 6: a late buffer callback cannot invalidate its replacement
--- config
    location /t {
        content_by_lua_block {
            local timer_at = ngx.timer.at
            local callback, owner, timer
            ngx.timer.at = function(delay, func, self, arg)
                if delay == 1 and not callback then
                    callback, owner, timer = func, self, arg
                    return true
                end
                return timer_at(delay, func, self, arg)
            end
            package.loaded["apisix.utils.batch-processor"] = nil
            local Batch = require("apisix.utils.batch-processor")
            ngx.timer.at = timer_at
            local sent = 0
            local processor = assert(Batch:new(function(entries)
                sent = sent + #entries
                return true
            end, {name = "late buffer", batch_max_size = 10, inactive_timeout = 1}))
            processor:push("first")
            ngx.sleep(2.2)
            assert(sent == 1)
            processor:push("second")
            callback(false, owner, timer)
            assert(processor.is_timer_running)
            ngx.sleep(1.2)
            assert(sent == 2)
            assert(processor.processed_entries == 2)
            ngx.say("flushed twice")
        }
    }
--- request
GET /t
--- response_body
flushed twice
--- error_log
recovering buffer timer
--- no_error_log
[error]
--- timeout: 10
