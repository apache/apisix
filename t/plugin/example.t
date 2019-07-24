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
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({i = 1, s = "s", t = {1}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: missing args
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")

            local ok, err = plugin.check_schema({s = "s", t = {1}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "required" in docuement at pointer "#"
done
--- no_error_log
[error]



=== TEST 3: small then minimum
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({i = -1, s = "s", t = {1, 2}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "minimum" in docuement at pointer "#/i"
done
--- no_error_log
[error]



=== TEST 4: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({i = 1, s = 123, t = {1}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "type" in docuement at pointer "#/s"
done
--- no_error_log
[error]



=== TEST 5: the size of array < minItems
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_schema({i = 1, s = '123', t = {}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "type" in docuement at pointer "#/t"
done
--- no_error_log
[error]



=== TEST 6: load plugins
--- config
    location /t {
        content_by_lua_block {
            local plugins, err = require("apisix.plugin").load()
            if not plugins then
                ngx.say("failed to load plugins: ", err)
            end

            local encode_json = require "cjson.safe" .encode
            for _, plugin in ipairs(plugins) do
                ngx.say("plugin name: ", plugin.name,
                        " priority: ", plugin.priority)

                plugin.rewrite()
            end
        }
    }
--- request
GET /t
--- response_body
plugin name: example-plugin priority: 1000
--- yaml_config
etcd:
  host: "http://127.0.0.1:2379" # etcd address
  prefix: "/apisix"             # apisix configurations prefix
  timeout: 1

plugins:
  - example-plugin
  - not-exist-plugin
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr/module 'apisix.plugins.not-exist-plugin' not found/



=== TEST 7: filter plugins
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")

            local all_plugins, err = plugin.load()
            if not all_plugins then
                ngx.say("failed to load plugins: ", err)
            end

            local filter_plugins = plugin.filter({
                value = {
                    plugins = {
                        ["example-plugin"] = {i = 1, s = "s", t = {1, 2}},
                        ["new-plugin"] = {a = "a"},
                    }
                },
                modifiedIndex = 1,
            })

            local encode_json = require "cjson.safe" .encode
            for i = 1, #filter_plugins, 2 do
                local plugin = filter_plugins[i]
                local plugin_conf = filter_plugins[i + 1]
                ngx.say("plugin [", plugin.name, "] config: ",
                        encode_json(plugin_conf))
            end
        }
    }
--- request
GET /t
--- response_body
plugin [example-plugin] config: {"i":1,"s":"s","t":[1,2]}
--- no_error_log
[error]



=== TEST 8: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "example-plugin": {
                                "i": 11,
                                "ip": "127.0.0.1",
                                "port": 1981
                            }
                        },
                        "uri": "/server_port"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: hit route
--- request
GET /server_port
--- response_body_like eval
qr/1981/
--- no_error_log
[error]
