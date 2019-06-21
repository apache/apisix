use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local core = require("apisix.core")
            local res, err = core.etcd.get("/node_status/" .. core.id.get())

            if res.status >= 300 then
                res.status = code
                ngx.print(res.body)
                return
            end

            local values = res.body.node.value

            for _, name in ipairs({"active", "accepted", "handled", "total",
                               "reading", "writing", "waiting"}) do
                ngx.say(name, " -> ", values[name])
            end
        }
    }
--- request
GET /t
--- response_body eval
qr/active -> \d
accepted -> \d
handled -> \d
total -> \d
reading -> \d
writing -> \d
waiting -> \d/
--- no_error_log
[error]
