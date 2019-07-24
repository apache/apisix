use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: get plugins' name
--- request
GET /apisix/admin/plugins/list
--- response_body_like eval
qr/example-plugin","limit-req","limit-count","key-auth","prometheus","limit-conn","node-status"/
--- no_error_log
[error]
