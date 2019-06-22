use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: sanity
--- request
GET /apisix/status
--- response_body eval
qr/"accepted":/
--- no_error_log
[error]
