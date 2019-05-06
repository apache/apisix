use t::APIMeta 'no_plan';

repeat_each(2);
no_long_string();
log_level('info');

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local apimeta = require("apimeta")
            apimeta.access()
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body_like eval
qr/404 Not Found/
