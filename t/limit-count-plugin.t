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
            apisix.access_phase()
        }
    }
--- request
POST /admin-api/applications/http
--- post_json
{
    "domains":[{"domain":"test.com","is_wildcard":false}],
    "name":"测试 SSL",
    "type":["http","https"]
}
--- response_ok
