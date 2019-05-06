use t::APIMeta 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
log_level('info');

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apimeta.plugins.example_plugin")
            local ok, err = plugin.check_args({i = 1, s = "s", t = {}})
            if not ok then
                ngx.say("failed to check args: ", err)
            end

            ok, err = plugin.check_args({s = "s", t = {}})
            if not ok then
                ngx.say("failed to check args: ", err)
            end

            ok, err = plugin.check_args({i = 1, s = 3, t = {}})
            if not ok then
                ngx.say("failed to check args: ", err)
            end

            ok, err = plugin.check_args({i = 1, s = "s", t = ""})
            if not ok then
                ngx.say("failed to check args: ", err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
failed to check args: key [i] should be a int
failed to check args: key [s] should be a string
failed to check args: key [t] should be a table
done
