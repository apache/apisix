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
qr/"upstream":\{"type":"object"/
--- no_error_log
[error]



=== TEST 3: get not exist schema
--- request
GET /apisix/admin/schema/noexits
--- error_code: 404
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
