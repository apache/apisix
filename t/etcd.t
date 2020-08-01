use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 11: invalid req_headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "http_path": "/status",
                    "host": "foo.com",
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    },
                    "req_headers": ["User-Agent: curl/7.29.0", 2233]
                }
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"checks\" validation failed: property \"active\" validation failed: property \"req_headers\" validation failed: failed to validate item 2: wrong type: expected string, got number"}
--- no_error_log
[error]
