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

            ngx.say("uid: ", core.id.get())
        }
    }
--- request
GET /t
--- response_body_like eval
qr/uid: [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
--- error_log
not found apisix uid, generate a new one
