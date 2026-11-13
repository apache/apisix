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

=== TEST 1: send invalid arguments for constructor
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count  = 2,
                batch_max_size = 1,
                retry_delay  = 0,
            }
            local func_to_send = function(elements)
                return true
            end
            local log_buffer, err = Batch:new("", config)

            if log_buffer then
                log_buffer:push({hello='world'})
                ngx.say("done")
            end

            if not log_buffer then
                ngx.say("failed")
            end

        }
    }
--- request
GET /t
--- response_body
failed
--- wait: 0.5



=== TEST 2: sanity
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local func_to_send = function(elements)
                return true
            end

            local config = {
                max_retry_count  = 2,
                batch_max_size = 1,
                retry_delay  = 0,
            }

            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({hello='world'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Batch Processor[log buffer] successfully processed the entries
--- wait: 0.5



=== TEST 3: batch processor timeout exceeded
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count  = 2,
                batch_max_size = 2,
                retry_delay  = 0,
                inactive_timeout = 1
            }
            local func_to_send = function(elements)
                return true
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({hello='world'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Batch Processor[log buffer] buffer duration exceeded, activating buffer flush
Batch Processor[log buffer] successfully processed the entries
--- wait: 3



=== TEST 4: batch processor batch max size exceeded
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count = 2,
                batch_max_size = 2,
                retry_delay = 0,
            }
            local func_to_send = function(elements)
                return true
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({hello='world'})
            log_buffer:push({hello='world'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Batch Processor[log buffer] buffer duration exceeded, activating buffer flush
--- error_log
Batch Processor[log buffer] batch max size has exceeded
Batch Processor[log buffer] successfully processed the entries
--- wait: 1



=== TEST 5: first failed to process and second try success
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local core = require("apisix.core")
            local retry = false
            local config = {
                max_retry_count  = 2,
                batch_max_size = 2,
                retry_delay  = 0,
            }
            local func_to_send = function(elements)
                if not retry then
                    retry = true
                    return false
                end
                return true
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({hello='world'})
            log_buffer:push({hello='world'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Batch Processor[log buffer] failed to process entries
Batch Processor[log buffer] successfully processed the entries
--- wait: 0.5



=== TEST 6: Exceeding max retry count
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count  = 2,
                batch_max_size = 2,
                retry_delay  = 0,
            }
            local func_to_send = function(elements)
                return false
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({hello='world'})
            log_buffer:push({hello='world'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Batch Processor[log buffer] buffer duration exceeded, activating buffer flush
--- error_log
Batch Processor[log buffer] failed to process entries
Batch Processor[log buffer] exceeded the max_retry_count
--- wait: 0.5



=== TEST 7: two batches
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local core = require("apisix.core")
            local count = 0
            local config = {
                max_retry_count  = 2,
                batch_max_size = 2,
                retry_delay  = 0,
            }
            local func_to_send = function(elements)
                count = count + 1
                core.log.info("batch[", count , "] sent")
                return true
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({hello='world'})
            log_buffer:push({hello='world'})
            log_buffer:push({hello='world'})
            log_buffer:push({hello='world'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Batch Processor[log buffer] activating flush due to no activity
--- error_log
batch[1] sent
batch[2] sent
--- wait: 0.5



=== TEST 8: batch processor retry count 0 and fail processing
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count  = 0,
                batch_max_size = 2,
                retry_delay  = 0,
            }
            local func_to_send = function(elements)
                return false
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({hello='world'})
            log_buffer:push({hello='world'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Batch Processor[log buffer] activating flush due to no activity
--- error_log
Batch Processor[log buffer] exceeded the max_retry_count
--- wait: 0.5



=== TEST 9: batch processor timeout exceeded
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count  = 2,
                batch_max_size = 2,
                retry_delay  = 0,
                buffer_duration = 60,
                inactive_timeout = 1,
            }
            local func_to_send = function(elements)
                return true
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({hello='world'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Batch Processor[log buffer] buffer duration exceeded, activating buffer flush
Batch Processor[log buffer] successfully processed the entries
--- wait: 3



=== TEST 10: json encode and log elements
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local core = require("apisix.core")
            local config = {
                max_retry_count  = 2,
                batch_max_size = 2,
                retry_delay  = 0,
            }
            local func_to_send = function(elements)
                core.log.info(require("toolkit.json").encode(elements))
                return true
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({msg='1'})
            log_buffer:push({msg='2'})
            log_buffer:push({msg='3'})
            log_buffer:push({msg='4'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Batch Processor[log buffer] activating flush due to no activity
--- error_log
[{"msg":"1"},{"msg":"2"}]
[{"msg":"3"},{"msg":"4"}]
--- wait: 0.5



=== TEST 11: extend timer
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local core = require("apisix.core")
            local config = {
                max_retry_count  = 1,
                batch_max_size = 3,
                retry_delay  = 0,
                inactive_timeout = 1
            }
            local func_to_send = function(elements)
                core.log.info(require("toolkit.json").encode(elements))
                return true
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({msg='1'})
            ngx.sleep(0.3)
            log_buffer:push({msg='2'})
            log_buffer:push({msg='3'})
            log_buffer:push({msg='4'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Batch Processor[log buffer] activating flush due to no activity
--- error_log
Batch Processor[log buffer] extending buffer timer
--- wait: 3



=== TEST 12: partially consumed entries
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local core = require("apisix.core")
            local config = {
                max_retry_count  = 1,
                batch_max_size = 3,
                retry_delay  = 0,
                inactive_timeout = 1
            }
            local func_to_send = function(elements)
                core.log.info(require("toolkit.json").encode(elements))
                return false, "error after consuming single entry", 2
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
            end

            log_buffer:push({msg='1'})
            log_buffer:push({msg='2'})
            log_buffer:push({msg='3'})
            log_buffer:push({msg='4'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
[{"msg":"1"},{"msg":"2"},{"msg":"3"}]
Batch Processor[log buffer] failed to process entries [2/3]: error after consuming single entry
[{"msg":"2"},{"msg":"3"}]
Batch Processor[log buffer] failed to process entries [1/2]: error after consuming single entry
[{"msg":"4"}]
--- wait: 2



=== TEST 13: batch processor exits cleanly during shutdown with active entries
# The real bug triggers when a buffer timer naturally expires (not via abort_pending_timers)
# during shutdown. With short inactive_timeout, the timer fires with premature=false while
# ngx.worker.exiting() is true. Without the exiting() check, flush_buffer would re-arm a
# zero-delay timer in an infinite loop, preventing worker exit.
# Using short timeouts + continuous pushing to create the race condition.
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local func_to_send = function(elements)
                return true
            end

            local config = {
                max_retry_count  = 0,
                batch_max_size = 1000,
                buffer_duration = 60,
                inactive_timeout = 1,
                retry_delay  = 0,
            }

            local log_buffer, err = Batch:new(func_to_send, config)
            if not log_buffer then
                ngx.say(err)
                return
            end

            -- push entries with short gaps to keep last_entry_t fresh
            local count = 0
            local function keep_pushing(premature)
                if premature then return end
                log_buffer:push({msg = "entry-" .. count})
                count = count + 1
                if count < 5 then
                    ngx.timer.at(0.3, keep_pushing)
                end
            end
            keep_pushing(false)
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- wait: 2



=== TEST 14: a callback that raises is retried and then dropped like one that returns false
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count  = 1,
                batch_max_size = 1,
                retry_delay  = 0,
            }
            local calls = 0
            local func_to_send = function(elements)
                calls = calls + 1
                error("callback raised on call " .. calls)
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
                return
            end

            log_buffer:push({hello='world'})
            -- wait for the call, its retry and the drop
            for _ = 1, 200 do
                if calls == 2 and log_buffer.processed_entries == 1 then
                    break
                end
                ngx.sleep(0.01)
            end
            ngx.say("calls: ", calls)
            ngx.say("processed: ", log_buffer.processed_entries)
        }
    }
--- request
GET /t
--- response_body
calls: 2
processed: 1
--- error_log eval
[qr/Batch Processor\[log buffer\] failed to process entries: .*callback raised on call 1/,
qr/Batch Processor\[log buffer\] failed to process entries: .*callback raised on call 2/,
qr/\[C\]: in function 'xpcall'/,
qr/Batch Processor\[log buffer\] exceeded the max_retry_count\[2\] dropping the entries/]
--- no_error_log
lua entry thread aborted



=== TEST 15: a batch dropped because its timer cannot be created still counts as processed
--- config
    location /t {
        content_by_lua_block {
            -- load a private copy of the module so that it captures a failing timer,
            -- and put the shared copy back for everything else
            local shared = package.loaded["apisix.utils.batch-processor"]
            package.loaded["apisix.utils.batch-processor"] = nil
            local timer_at = ngx.timer.at
            ngx.timer.at = function()
                return nil, "too many pending timers"
            end
            local Batch = require("apisix.utils.batch-processor")
            ngx.timer.at = timer_at
            package.loaded["apisix.utils.batch-processor"] = shared

            local config = {
                max_retry_count  = 0,
                batch_max_size = 1,
                retry_delay  = 0,
            }
            local log_buffer, err = Batch:new(function() return true end, config)

            if not log_buffer then
                ngx.say(err)
                return
            end

            log_buffer:push({hello='world'})
            ngx.say("processed: ", log_buffer.processed_entries)
        }
    }
--- request
GET /t
--- response_body
processed: 1
--- error_log
failed to create process timer: too many pending timers



=== TEST 16: a batch dropped because no timer can be created while exiting still counts as processed
--- config
    location /t {
        content_by_lua_block {
            -- load a private copy of the module so that it captures a failing timer,
            -- and put the shared copy back for everything else
            local shared = package.loaded["apisix.utils.batch-processor"]
            package.loaded["apisix.utils.batch-processor"] = nil
            local timer_at = ngx.timer.at
            ngx.timer.at = function()
                return nil, "process exiting"
            end
            local Batch = require("apisix.utils.batch-processor")
            ngx.timer.at = timer_at
            package.loaded["apisix.utils.batch-processor"] = shared

            local config = {
                max_retry_count  = 0,
                batch_max_size = 1,
                retry_delay  = 0,
            }
            local log_buffer, err = Batch:new(function() return true end, config)

            if not log_buffer then
                ngx.say(err)
                return
            end

            log_buffer:push({hello='world'})
            ngx.say("processed: ", log_buffer.processed_entries)
        }
    }
--- request
GET /t
--- response_body
processed: 1
--- error_log
failed to create fallback process timer while exiting: process exiting



=== TEST 17: a callback that returns a table as its error is still counted
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count  = 0,
                batch_max_size = 1,
                retry_delay  = 0,
            }
            local calls = 0
            local func_to_send = function(elements)
                calls = calls + 1
                return false, {reason = "rejected by the log server"}
            end
            local log_buffer, err = Batch:new(func_to_send, config)

            if not log_buffer then
                ngx.say(err)
                return
            end

            log_buffer:push({hello='world'})
            for _ = 1, 200 do
                if log_buffer.processed_entries == 1 then
                    break
                end
                ngx.sleep(0.01)
            end
            ngx.say("calls: ", calls)
            ngx.say("processed: ", log_buffer.processed_entries)
        }
    }
--- request
GET /t
--- response_body
calls: 1
processed: 1
--- error_log eval
qr/Batch Processor\[log buffer\] failed to process entries: table: 0x/
--- no_error_log
lua entry thread aborted
