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
qr/\["limit-req","limit-count","limit-conn","key-auth","prometheus","node-status","jwt-auth","zipkin","ip-restriction","grpc-transcode","serverless-pre-function","serverless-post-function","openid-connect"\]/
--- no_error_log
[error]
