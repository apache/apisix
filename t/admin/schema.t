use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: get route schema
--- request
GET /apisix/admin/schema/route
--- response_body eval
qr/"plugins": \{"type":"object"}/
--- no_error_log
[error]



=== TEST 2: get service schema
--- request
GET /apisix/admin/schema/service
--- response_body eval
qr/"required":\["upstream"\]/
--- no_error_log
[error]



=== TEST 3: get not exist schema
--- request
GET /apisix/admin/schema/noexits
--- error_code: 400
--- no_error_log
[error]



=== TEST 4: wrong method
--- request
PUT /apisix/admin/schema/service
--- error_code: 404
--- no_error_log
[error]



=== TEST 5: wrong method
--- request
POST /apisix/admin/schema/service
--- error_code: 404
--- no_error_log
[error]



=== TEST 6: ssl
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/schema/ssl',
            ngx.HTTP_GET,
            nil,
            {
                type = "object",
                properties = {
                    cert = {
                        type = "string", minLength = 128, maxLength = 4096
                    },
                    key = {
                        type = "string", minLength = 128, maxLength = 4096
                    },
                    sni = {
                        type = "string",
                        pattern = [[^\*?[0-9a-zA-Z-.]+$]],
                    }
                },
                required = {"sni", "key", "cert"},
                additionalProperties = false,
            }
            )

        ngx.status = code
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: get plugin's schema
--- request
GET /apisix/admin/schema/plugins/limit-count
--- response_body eval
qr/"required":\["count","time_window","key","rejected_code"]/
--- no_error_log
[error]



=== TEST 8: get not exist plugin
--- request
GET /apisix/admin/schema/plugins/no-exist
--- error_code: 400
--- no_error_log
[error]
