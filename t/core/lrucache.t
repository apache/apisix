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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local idx = 0
            local function create_obj()
                idx = idx + 1
                return {idx = idx}
            end

            local obj = core.lrucache.global("key", nil, create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = core.lrucache.global("key", nil, create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = core.lrucache.global("key", "1", create_obj)
            ngx.say("obj: ", core.json.encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1}
obj: {"idx":1}
obj: {"idx":2,"_cache_ver":"1"}
--- no_error_log
[error]



=== TEST 2: plugin
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local idx = 0
            local function create_obj()
                idx = idx + 1
                return {idx = idx}
            end

            local obj = core.lrucache.plugin("plugin-a", "key", nil, create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = core.lrucache.plugin("plugin-a", "key", nil, create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = core.lrucache.plugin("plugin-a", "key", "1", create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = core.lrucache.plugin("plugin-b", "key", "1", create_obj)
            ngx.say("obj: ", core.json.encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1}
obj: {"idx":1}
obj: {"idx":2,"_cache_ver":"1"}
obj: {"idx":3,"_cache_ver":"1"}
--- no_error_log
[error]



=== TEST 3: new
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local idx = 0
            local function create_obj()
                idx = idx + 1
                return {idx = idx}
            end

            local lru_get = core.lrucache.new()

            local obj = lru_get("key", nil, create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = lru_get("key", nil, create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = lru_get("key", "1", create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = lru_get("key", "1", create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            obj = lru_get("key-different", "1", create_obj)
            ngx.say("obj: ", core.json.encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1}
obj: {"idx":1}
obj: {"idx":2,"_cache_ver":"1"}
obj: {"idx":2,"_cache_ver":"1"}
obj: {"idx":3,"_cache_ver":"1"}
--- no_error_log
[error]



=== TEST 4: cache the non-table object, eg: number or string
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local idx = 0
            local function create_num()
                idx = idx + 1
                return idx
            end

            local obj = core.lrucache.global("key", nil, create_num)
            ngx.say("obj: ", core.json.encode(obj))

            obj = core.lrucache.global("key", nil, create_num)
            ngx.say("obj: ", core.json.encode(obj))

            obj = core.lrucache.global("key", "1", create_num)
            ngx.say("obj: ", core.json.encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: 1
obj: 1
obj: 2
--- no_error_log
[error]



=== TEST 5: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local function server_release(self)
                ngx.say("release: ", core.json.encode(self))
            end

            local lrucache_server_picker = core.lrucache.new({
                ttl = 300, count = 256, release = server_release,
            })

            local t1 = lrucache_server_picker("nnn", "t1",
                function () return {name = "aaa"} end)

            ngx.say("obj: ", core.json.encode(t1))

            local t2 = lrucache_server_picker("nnn", "t2",
                function () return {name = "bbb"} end)

            ngx.say("obj: ", core.json.encode(t2))
        }
    }
--- request
GET /t
--- response_body
obj: {"_cache_ver":"t1","name":"aaa"}
release: {"_cache_ver":"t1","name":"aaa"}
obj: {"_cache_ver":"t2","name":"bbb"}
--- no_error_log
[error]



=== TEST 6: invalid_stale = true
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local idx = 0
            local function create_obj()
                idx = idx + 1
                return {idx = idx}
            end

            local lru_get = core.lrucache.new({
                ttl = 0.1, count = 256, invalid_stale = true,
            })

            local obj = lru_get("key", "ver", create_obj)
            ngx.say("obj: ", core.json.encode(obj))
            local obj = lru_get("key", "ver", create_obj)
            ngx.say("obj: ", core.json.encode(obj))

            ngx.sleep(0.15)
            local obj = lru_get("key", "ver", create_obj)
            ngx.say("obj: ", core.json.encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1,"_cache_ver":"ver"}
obj: {"idx":1,"_cache_ver":"ver"}
obj: {"idx":2,"_cache_ver":"ver"}
--- no_error_log
[error]



=== TEST 7: when creating cached objects, use resty-lock to avoid repeated creation.
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local idx = 0
            local function create_obj()
                idx = idx + 1
                ngx.sleep(0.1)
                return {idx = idx}
            end

            local lru_get = core.lrucache.new({
                ttl = 1, count = 256, invalid_stale = true,
            })

            local function f()
                local obj = lru_get("key", "ver", create_obj)
                ngx.say("obj: ", core.json.encode(obj))
            end

            ngx.thread.spawn(f)
            ngx.thread.spawn(f)

            ngx.sleep(0.3)
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1,"_cache_ver":"ver"}
obj: {"idx":1,"_cache_ver":"ver"}
--- no_error_log
[error]
