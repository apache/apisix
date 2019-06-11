use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: roundrobin with same weight
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local balancer = require("apisix.balancer")

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

            local res = {}
            for i=1,12 do
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
            local balancer = require("apisix.balancer")

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

            local res = {}
            for i=1,12 do
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
            local core = require("apisix.core")
            local balancer = require("apisix.balancer")

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

            local res = {}
            for i=1,12 do
                if i == 2 then
                    route.value.upstream.nodes = {
                        ["39.97.63.218:83"] = 1,
                    }
                end

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
