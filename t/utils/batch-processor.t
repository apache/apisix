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
                process_delay  = 0,
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
                process_delay  = 0,
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
                process_delay  = 0,
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
BatchProcessor[log buffer] buffer duration exceeded, activating buffer flush
Batch Processor[log buffer] successfully processed the entries
--- wait: 3



=== TEST 4: batch processor batch max size exceeded
--- config
    location /t {
        content_by_lua_block {
            local Batch = require("apisix.utils.batch-processor")
            local config = {
                max_retry_count  = 2,
                batch_max_size = 2,
                process_delay  = 0,
                retry_delay  = 0,
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
BatchProcessor[log buffer] activating flush due to no activity
--- error_log
batch processor[log buffer] batch max size has exceeded
Batch Processor[log buffer] successfully processed the entries
--- wait: 0.5



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
                process_delay  = 0,
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
                process_delay  = 0,
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
BatchProcessor[log buffer] buffer duration exceeded, activating buffer flush
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
                process_delay  = 0,
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
BatchProcessor[log buffer] activating flush due to no activity
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
                process_delay  = 0,
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
BatchProcessor[log buffer] activating flush due to no activity
Batch Processor[log buffer] failed to process entries
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
                process_delay  = 0,
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
BatchProcessor[log buffer] buffer duration exceeded, activating buffer flush
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
                process_delay  = 0,
                retry_delay  = 0,
            }
            local func_to_send = function(elements)
                core.log.info(core.json.encode(elements))
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
BatchProcessor[log buffer] activating flush due to no activity
--- error_log
[{"msg":"1"},{"msg":"2"}]
[{"msg":"3"},{"msg":"4"}]
--- wait: 0.5
