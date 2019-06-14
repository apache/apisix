use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
no_long_string();
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set invalid route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/routes/1", [[mexxxxxxxxxxxxxxx]])

            if res.status >= 300 then
                res.status = code
            end

            ngx.print(core.json.encode(res.body))
            ngx.sleep(1)
        }
    }
--- request
GET /t
--- error_log
failed to check item data of [/apisix/routes] err:invalid
--- response_body_like eval
qr/"value":"mexxxxxxxxxxxxxxx"/



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body_like eval
qr/404 Not Found/
--- error_log
failed to check item data of [/apisix/routes] err:invalid



=== TEST 3: delete invalid route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.delete("/routes/1")

            if res.status >= 300 then
                res.status = code
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
