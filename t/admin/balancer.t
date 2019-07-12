use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $init_by_lua_block = <<_EOC_;
    require "resty.core"
    apisix = require("apisix")
    apisix.http_init()

    function test(route, ctx, count)
        local balancer = require("apisix.http.balancer")
        local res = {}
        for i = 1, count or 12 do
            local host, port, err = balancer.pick_server(route, ctx)
            if err then
                ngx.say("failed: ", err)
            end
            res[host] = (res[host] or 0) + 1
        end

        local keys = {}
        for k,v in pairs(res) do
            table.insert(keys, k)
        end
        table.sort(keys)

        for _, key in ipairs(keys) do
            ngx.say("host: ", key, " count: ", res[key])
        end
    end
_EOC_
    $block->set_value("init_by_lua_block", $init_by_lua_block);
});

run_tests;

__DATA__

=== TEST 1: roundrobin with same weight
--- config
    location /t {
        content_by_lua_block {
            local route = {
                    value = {
                        upstream = {
                            nodes = {
                                ["39.97.63.215:80"] = 1,
                                ["39.97.63.216:81"] = 1,
                                ["39.97.63.217:82"] = 1,
                            },
                            type = "roundrobin",
                        },
                        id = 1
                    }
                }
            local ctx = {conf_version = 1}

            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 4
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 4
--- no_error_log
[error]



=== TEST 2: roundrobin with different weight
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local balancer = require("apisix.http.balancer")

            local route = {
                    value = {
                        upstream = {
                            nodes = {
                                ["39.97.63.215:80"] = 1,
                                ["39.97.63.216:81"] = 2,
                                ["39.97.63.217:82"] = 3,
                            },
                            type = "roundrobin",
                        },
                        id = 1
                    }
                }
            local ctx = {conf_version = 1}

            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 2
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 6
--- no_error_log
[error]



=== TEST 3: roundrobin, cached server picker by version
--- config
    location /t {
        content_by_lua_block {
            local balancer = require("apisix.http.balancer")

            local route = {
                    value = {
                        upstream = {
                            nodes = {
                                ["39.97.63.215:80"] = 1,
                                ["39.97.63.216:81"] = 1,
                                ["39.97.63.217:82"] = 1,
                            },
                            type = "roundrobin",
                        },
                        id = 1
                    }
                }
            local ctx = {conf_version = 1}

            test(route, ctx)

            -- cached by version
            route.value.upstream.nodes = {
                ["39.97.63.218:83"] = 1,
            }
            test(route, ctx)

            -- update, version changed
            ctx = {conf_version = 2}
            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 4
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 4
host: 39.97.63.215 count: 4
host: 39.97.63.216 count: 4
host: 39.97.63.217 count: 4
host: 39.97.63.218 count: 12
--- no_error_log
[error]



=== TEST 4: chash
--- config
    location /t {
        content_by_lua_block {
            local route = {
                    value = {
                        upstream = {
                            nodes = {
                                ["39.97.63.215:80"] = 1,
                                ["39.97.63.216:81"] = 1,
                                ["39.97.63.217:82"] = 1,
                            },
                            type = "chash",
                            key  = "remote_addr",
                        },
                        id = 1
                    }
                }
            local ctx = {
                conf_version = 1,
                var = {
                    remote_addr = "127.0.0.1"
                }
            }

            test(route, ctx)

            -- cached by version
            route.value.upstream.nodes = {
                ["39.97.63.218:83"] = 1,
            }
            test(route, ctx)

            -- update, version changed
            ctx.conf_version = 2
            test(route, ctx)
        }
    }
--- request
GET /t
--- response_body
host: 39.97.63.215 count: 12
host: 39.97.63.215 count: 12
host: 39.97.63.218 count: 12
--- no_error_log
[error]
