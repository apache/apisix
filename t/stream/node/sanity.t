use t::APISIX 'no_plan';

repeat_each(2);
no_root_location();

run_tests();

__DATA__

=== TEST 1: basic print
--- stream_response
hello world
--- no_error_log
[error]
