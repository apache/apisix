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
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            obj = core.lrucache.global("key", nil, create_obj)
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            obj = core.lrucache.global("key", "1", create_obj)
            ngx.say("obj: ", require("toolkit.json").encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1}
obj: {"idx":1}
obj: {"idx":2}



=== TEST 2: new
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
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            obj = lru_get("key", nil, create_obj)
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            obj = lru_get("key", "1", create_obj)
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            obj = lru_get("key", "1", create_obj)
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            obj = lru_get("key-different", "1", create_obj)
            ngx.say("obj: ", require("toolkit.json").encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1}
obj: {"idx":1}
obj: {"idx":2}
obj: {"idx":2}
obj: {"idx":3}



=== TEST 3: cache the non-table object, eg: number or string
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
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            obj = core.lrucache.global("key", nil, create_num)
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            obj = core.lrucache.global("key", "1", create_num)
            ngx.say("obj: ", require("toolkit.json").encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: 1
obj: 1
obj: 2



=== TEST 4: invalid_stale = true
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
            ngx.say("obj: ", require("toolkit.json").encode(obj))
            local obj = lru_get("key", "ver", create_obj)
            ngx.say("obj: ", require("toolkit.json").encode(obj))

            ngx.sleep(0.15)
            local obj = lru_get("key", "ver", create_obj)
            ngx.say("obj: ", require("toolkit.json").encode(obj))
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1}
obj: {"idx":1}
obj: {"idx":2}



=== TEST 5: when creating cached objects, use resty-lock to avoid repeated creation.
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
                ttl = 1, count = 256, invalid_stale = true, serial_creating = true,
            })

            local function f()
                local obj = lru_get("key", "ver", create_obj)
                ngx.say("obj: ", require("toolkit.json").encode(obj))
            end

            ngx.thread.spawn(f)
            ngx.thread.spawn(f)

            ngx.sleep(0.3)
        }
    }
--- request
GET /t
--- response_body
obj: {"idx":1}
obj: {"idx":1}



=== TEST 6: different `key` and `ver`, cached same one table
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local item = {}
            local idx = 0
            local function create_obj()
                idx = idx + 1
                ngx.say("create obj ", idx, " time")
                return item
            end

            local lru_get = core.lrucache.new({
                ttl = 10, count = 256
            })

            local obj = lru_get("key", "ver", create_obj)
            ngx.say("fetch obj: ", obj == item)

            obj = lru_get("key2", "ver2", create_obj)
            ngx.say("fetch obj: ", obj == item)

            obj = lru_get("key", "ver", create_obj)
            ngx.say("fetch obj: ", obj == item)
        }
    }
--- request
GET /t
--- response_body
create obj 1 time
fetch obj: true
create obj 2 time
fetch obj: true
fetch obj: true



=== TEST 7: a dropped lrucache releases its cached objects
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local lru_get = core.lrucache.new({
                ttl = 10, count = 256, invalid_stale = true, refresh_stale = true,
            })
            local probe = setmetatable({}, {__mode = "v"})
            lru_get("key", "ver", function ()
                local obj = {}
                probe[1] = obj
                return obj
            end)

            lru_get = nil
            collectgarbage()
            collectgarbage()
            ngx.say("released: ", probe[1] == nil)
        }
    }
--- request
GET /t
--- response_body
released: true



=== TEST 8: inactive: an item not accessed within `inactive` is purged
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local lru_get = core.lrucache.new({
                ttl = 1, count = 256, invalid_stale = true, refresh_stale = true,
                inactive = 1,
            })
            local probe = setmetatable({}, {__mode = "v"})
            local created = 0
            local function create_obj()
                created = created + 1
                local obj = {}
                probe[created] = obj
                return obj
            end

            lru_get("key", "ver", create_obj)
            -- purged once the 1s purge timer runs after `inactive`
            local deadline = ngx.now() + 5
            repeat
                ngx.sleep(0.2)
                collectgarbage()
                collectgarbage()
            until probe[1] == nil or ngx.now() > deadline
            ngx.say("released: ", probe[1] == nil)

            lru_get("key", "ver", create_obj)
            ngx.say("created: ", created)
        }
    }
--- request
GET /t
--- response_body
released: true
created: 2
--- timeout: 8



=== TEST 9: inactive: an item still in use is kept while its refresh keeps failing
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local lru_get = core.lrucache.new({
                ttl = 0.5, count = 256, invalid_stale = true, refresh_stale = true,
                inactive = 1,
            })
            local created = 0
            local function create_obj()
                created = created + 1
                if created > 1 then
                    return nil, "refresh failure"
                end
                return {gen = created}
            end

            local obj = lru_get("key", "ver", create_obj)
            local same = true
            for _ = 1, 10 do
                ngx.sleep(0.3)
                if lru_get("key", "ver", create_obj) ~= obj then
                    same = false
                end
            end
            ngx.say("served the first object: ", same)
            ngx.say("refreshed: ", created > 1)
        }
    }
--- request
GET /t
--- response_body
served the first object: true
refreshed: true
--- error_log
refresh failure
--- timeout: 6



=== TEST 10: inactive: purging an item drops its pending refresh
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local lru_get = core.lrucache.new({
                ttl = 0.2, count = 256, invalid_stale = true, refresh_stale = true,
                inactive = 1,
            })
            local created = 0
            local function create_obj()
                created = created + 1
                if created > 1 then
                    return nil, "refresh failure"
                end
                return {}
            end

            lru_get("key", "ver", create_obj)
            ngx.sleep(0.3)
            -- served stale, queues a refresh that keeps failing
            lru_get("key", "ver", create_obj)
            -- the purge itself is not observable here: leave it a wide margin
            ngx.sleep(3.5)
            local after_purge = created
            ngx.sleep(2.5)
            ngx.say("refresh retried after the purge: ", created > after_purge)
        }
    }
--- request
GET /t
--- response_body
refresh retried after the purge: false
--- error_log
refresh failure
--- timeout: 10



=== TEST 11: inactive: a refresh in flight does not bring a purged item back
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local lru_get = core.lrucache.new({
                ttl = 0.5, count = 256, invalid_stale = true, refresh_stale = true,
                inactive = 1,
            })
            local created = 0
            local function create_obj()
                created = created + 1
                local gen = created
                if ngx.get_phase() == "timer" then
                    -- the item is purged while this refresh is running
                    ngx.sleep(4)
                end
                return {gen = gen}
            end

            lru_get("key", "ver", create_obj)
            ngx.sleep(0.6)
            -- served stale, queues the slow refresh
            lru_get("key", "ver", create_obj)
            ngx.sleep(5.5)

            ngx.say("gen: ", lru_get("key", "ver", create_obj).gen)
        }
    }
--- request
GET /t
--- response_body
gen: 3
--- timeout: 10



=== TEST 12: inactive: a dropped lrucache releases its cached objects
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local lru_get = core.lrucache.new({
                ttl = 10, count = 256, invalid_stale = true, refresh_stale = true,
                inactive = 10,
            })
            local probe = setmetatable({}, {__mode = "v"})
            lru_get("key", "ver", function ()
                local obj = {}
                probe[1] = obj
                return obj
            end)

            lru_get = nil
            collectgarbage()
            collectgarbage()
            ngx.say("released: ", probe[1] == nil)
        }
    }
--- request
GET /t
--- response_body
released: true



=== TEST 13: an lrucache without inactive keeps idle items
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local lru_get = core.lrucache.new({ttl = 0.5, count = 256})
            local created = 0
            local function create_obj()
                created = created + 1
                return {}
            end

            local obj = lru_get("key", "ver", create_obj)
            ngx.sleep(2.5)
            ngx.say("same object: ", lru_get("key", "ver", create_obj) == obj)
            ngx.say("created: ", created)
        }
    }
--- request
GET /t
--- response_body
same object: true
created: 1
--- timeout: 5
