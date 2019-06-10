use t::APISix 'no_plan';

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
