use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");
workers(2);
master_on();

run_tests;

__DATA__

=== TEST 1: reload plugins
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, _, org_body = t('/apisix/admin/plugins/reload',
                                    ngx.HTTP_PUT)

        ngx.status = code
        ngx.print(org_body)
        ngx.sleep(0.2)
    }
}
--- request
GET /t
--- response_body
done
--- error_log
load plugin times: 1
load plugin times: 1
start to hot reload plugins
start to hot reload plugins
load plugin times: 2
load plugin times: 2
