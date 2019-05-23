use t::APISix 'no_plan';

repeat_each(2);
log_level('info');
no_root_location();

run_tests();

__DATA__

=== TEST 1: not found
--- config
    location /t {
        content_by_lua_block {
            local apisix = require("apisix")
            apisix.rewrite_phase()
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
