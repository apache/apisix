use t::APISIX 'no_plan';

repeat_each(1);
worker_connections(1024);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: bad page_size(page_size must be between 10 and 500)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            ngx.sleep(0.5)

            local code, body = t('/apisix/admin/routes/?page=&page_size=2',
                ngx.HTTP_GET
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body
page_size must be between 10 and 500



=== TEST 2: ignore bad page and would use default value 1
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?page=-1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 10)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: sort by createdIndex
# the smaller the createdIndex, the higher the ranking
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?page=1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)

            for i = 1, #res.list - 1 do
                assert(res.list[i].createdIndex < res.list[i + 1].createdIndex)
            end
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: routes pagination
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. i .. [["
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/routes/?page=1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 10)

            code, body, res = t('/apisix/admin/routes/?page=2&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 1)

            code, body, res = t('/apisix/admin/routes/?page=3&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 0)

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: services pagination
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            for i = 1, 11 do
                local code, body = t('/apisix/admin/services/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                    }]]
                )
            end

            ngx.sleep(0.5)

            local code, body, res = t('/apisix/admin/services/?page=1&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 10)

            code, body, res = t('/apisix/admin/services/?page=2&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 1)

            code, body, res = t('/apisix/admin/services/?page=3&page_size=10',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            assert(#res.list == 0)

            ngx.say(body)
        }
    }
--- response_body
passed
