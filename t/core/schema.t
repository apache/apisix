use t::APISIX 'no_plan';

repeat_each(2);
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
            local schema = {
                type = "object",
                properties = {
                    i = {type = "number", minimum = 0},
                    s = {type = "string"},
                    t = {type = "array", minItems = 1},
                }
            }

            for i = 1, 10 do
                local ok, err = core.schema.check(schema,
                                    {i = i, s = "s" .. i, t = {i}})
                assert(ok)
                assert(err == nil)
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: same schema in different timer
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local schema = {
                type = "object",
                properties = {
                    i = {type = "number", minimum = 0},
                    s = {type = "string"},
                    t = {type = "array", minItems = 1},
                }
            }

            local count = 0
            local function test()
                for i = 1, 10 do
                    local ok, err = core.schema.check(schema,
                                        {i = i, s = "s" .. i, t = {i}})
                    assert(ok)
                    assert(err == nil)
                    count = count + 1
                end
            end

            ngx.timer.at(0, test)
            ngx.timer.at(0, test)
            ngx.timer.at(0, test)

            ngx.sleep(1)
            ngx.say("passed: ", count)
        }
    }
--- request
GET /t
--- response_body
passed: 30
--- no_error_log
[error]



=== TEST 3: collectgarbage
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local schema = {
                type = "object",
                properties = {
                    i = {type = "number", minimum = 0},
                    s = {type = "string"},
                    t = {type = "array", minItems = 1},
                }
            }

            for i = 1, 1000 do
                collectgarbage()
                local ok, err = core.schema.check(schema,
                                    {i = i, s = "s" .. i, t = {i}})
                assert(ok)
                assert(err == nil)
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
