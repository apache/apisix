use t::APISIX 'no_plan';

repeat_each(2);
no_root_location();

run_tests();

__DATA__

=== TEST 1: sanity
--- stream_enable
--- stream_response
hello world
--- no_error_log
[error]
