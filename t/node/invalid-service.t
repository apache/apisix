use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
no_long_string();
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set invalid service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/services/1", [[mexxxxxxxxxxxxxxx]])

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
invalid item data of [/apisix/services/1], val: mexxxxxxxxxxxxxxx, it shoud be a object
--- response_body_like eval
qr/"value":"mexxxxxxxxxxxxxxx"/



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body_like eval
qr/404 Not Found/
--- error_log
invalid item data of [/apisix/services/1], val: mexxxxxxxxxxxxxxx, it shoud be a object



=== TEST 3: set valid service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local res, err = core.etcd.set("/services/1", core.json.decode([[{
                        "plugins": {},
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                }]]))

            if res.status >= 300 then
                res.status = code
            end

            ngx.print(core.json.encode(res.body))
        }
    }
--- request
GET /t
--- response_body_like eval
qr/"nodes":\{"127.0.0.1:1980":1\}/
--- error_log
invalid item data of [/apisix/services/1], val: mexxxxxxxxxxxxxxx, it shoud be a object
