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
no_long_string();
no_root_location();
log_level("info");

run_tests;

__DATA__

=== TEST 1: negative cache basic functionality
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local call_count = 0
            local function create_obj_fail()
                call_count = call_count + 1
                return nil, "simulated failure"
            end

            -- create LRU cache with negative caching
            local lru_get = core.lrucache.new({
                ttl = 1,
                count = 256,
                neg_ttl = 0.5,  -- shorter TTL for failures
                neg_count = 128
            })

            -- First call should execute the function and cache the failure
            local obj, err = lru_get("fail_key", "v1", create_obj_fail)
            ngx.say("call_count after first call: ", call_count)
            ngx.say("first call result: obj=", tostring(obj), ", err=", tostring(err))

            -- Second call should return from negative cache without calling create_obj_fail
            obj, err = lru_get("fail_key", "v1", create_obj_fail)
            ngx.say("call_count after second call: ", call_count)
            ngx.say("second call result: obj=", tostring(obj), ", err=", tostring(err))

            -- Different version should bypass negative cache
            obj, err = lru_get("fail_key", "v2", create_obj_fail)
            ngx.say("call_count after different version: ", call_count)
            ngx.say("different version result: obj=", tostring(obj), ", err=", tostring(err))
        }
    }
--- request
GET /t
--- response_body
call_count after first call: 1
first call result: obj=nil, err=simulated failure
call_count after second call: 1
second call result: obj=nil, err=simulated failure
call_count after different version: 2
different version result: obj=nil, err=simulated failure



=== TEST 2: negative cache TTL expiration
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local call_count = 0
            local function create_obj_fail()
                call_count = call_count + 1
                return nil, "simulated failure"
            end

            -- Create LRU cache with very short negative TTL
            local lru_get = core.lrucache.new({
                ttl = 10,
                count = 256,
                neg_ttl = 0.1,  -- very short TTL for failures
                neg_count = 128
            })

            -- First call
            local obj, err = lru_get("fail_key", "v1", create_obj_fail)
            ngx.say("call_count after first call: ", call_count)

            -- Immediate second call - should use negative cache
            obj, err = lru_get("fail_key", "v1", create_obj_fail)
            ngx.say("call_count after immediate call: ", call_count)

            -- Wait for negative cache to expire
            ngx.sleep(0.15)

            -- This should call create_obj_fail again
            obj, err = lru_get("fail_key", "v1", create_obj_fail)
            ngx.say("call_count after TTL expiration: ", call_count)
        }
    }
--- request
GET /t
--- response_body
call_count after first call: 1
call_count after immediate call: 1
call_count after TTL expiration: 2



=== TEST 3: mixed success and failure caching
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local success_count = 0
            local fail_count = 0

            local function create_obj_success()
                success_count = success_count + 1
                return {value = "success_" .. success_count}
            end

            local function create_obj_fail()
                fail_count = fail_count + 1
                return nil, "failure_" .. fail_count
            end

            local lru_get = core.lrucache.new({
                ttl = 1,
                count = 256,
                neg_ttl = 0.5,
                neg_count = 128
            })

            -- Test success caching
            local obj1 = lru_get("success_key", "v1", create_obj_success)
            ngx.say("success_count after first success: ", success_count)
            ngx.say("success value: ", obj1.value)

            local obj2 = lru_get("success_key", "v1", create_obj_success)
            ngx.say("success_count after cached success: ", success_count)
            ngx.say("cached success value: ", obj2.value)

            -- Test failure caching
            local obj3, err3 = lru_get("fail_key", "v1", create_obj_fail)
            ngx.say("fail_count after first failure: ", fail_count)
            ngx.say("failure error: ", err3)

            local obj4, err4 = lru_get("fail_key", "v1", create_obj_fail)
            ngx.say("fail_count after cached failure: ", fail_count)
            ngx.say("cached failure error: ", err4)
        }
    }
--- request
GET /t
--- response_body
success_count after first success: 1
success value: success_1
success_count after cached success: 1
cached success value: success_1
fail_count after first failure: 1
failure error: failure_1
fail_count after cached failure: 1
cached failure error: failure_1



=== TEST 4: negative cache with different keys
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local call_count = 0
            local function create_obj_fail(key)
                call_count = call_count + 1
                return nil, "failed for " .. key
            end

            local lru_get = core.lrucache.new({
                ttl = 1,
                count = 256,
                neg_ttl = 0.5,
                neg_count = 128
            })

            -- First key
            local obj1, err1 = lru_get("key1", "v1", create_obj_fail, "key1")
            ngx.say("call_count after key1: ", call_count)

            -- Second key
            local obj2, err2 = lru_get("key2", "v1", create_obj_fail, "key2")
            ngx.say("call_count after key2: ", call_count)

            -- Repeat key1 - should use negative cache
            local obj3, err3 = lru_get("key1", "v1", create_obj_fail, "key1")
            ngx.say("call_count after key1 repeat: ", call_count)
            ngx.say("key1 error: ", err3)

            -- Repeat key2 - should use negative cache
            local obj4, err4 = lru_get("key2", "v1", create_obj_fail, "key2")
            ngx.say("call_count after key2 repeat: ", call_count)
            ngx.say("key2 error: ", err4)
        }
    }
--- request
GET /t
--- response_body
call_count after key1: 1
call_count after key2: 2
call_count after key1 repeat: 2
key1 error: failed for key1
call_count after key2 repeat: 2
key2 error: failed for key2



=== TEST 5: negative cache respects version changes
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local call_count = 0
            local function create_obj_fail(version)
                call_count = call_count + 1
                return nil, "failed for version " .. version
            end

            local lru_get = core.lrucache.new({
                ttl = 10,
                count = 256,
                neg_ttl = 10,
                neg_count = 128
            })

            -- Call with version 1
            local obj1, err1 = lru_get("version_key", "v1", create_obj_fail, "v1")
            ngx.say("call_count after v1: ", call_count)

            -- Call with version 1 again - should use negative cache
            local obj2, err2 = lru_get("version_key", "v1", create_obj_fail, "v1")
            ngx.say("call_count after v1 repeat: ", call_count)

            -- Call with version 2 - should bypass negative cache
            local obj3, err3 = lru_get("version_key", "v2", create_obj_fail, "v2")
            ngx.say("call_count after v2: ", call_count)

            -- Call with version 2 again - should use negative cache
            local obj4, err4 = lru_get("version_key", "v2", create_obj_fail, "v2")
            ngx.say("call_count after v2 repeat: ", call_count)
        }
    }
--- request
GET /t
--- response_body
call_count after v1: 1
call_count after v1 repeat: 1
call_count after v2: 2
call_count after v2 repeat: 2
