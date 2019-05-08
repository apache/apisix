use t::APIMeta 'no_plan';

repeat_each(2);
no_root_location();

run_tests();

__DATA__

=== TEST 1: not found
--- config
    location /t {
        content_by_lua_block {
            local apimeta = require("apimeta")
            apimeta.rewrite()
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body_like eval
qr/404 Not Found/



=== TEST 2: default response
--- request
GET /not_found
--- error_code: 404
--- response_body_like eval
qr/404 Not Found/
