use t::APISIX 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = {"first"}
            core.table.insert_tail(t, 'a', 1, true)

            ngx.say("encode: ", core.json.encode(t))

            core.table.set(t, 'a', 1, true)
            ngx.say("encode: ", core.json.encode(t))
        }
    }
--- request
GET /t
--- response_body
encode: ["first","a",1,true]
encode: ["a",1,true,true]
--- no_error_log
[error]
