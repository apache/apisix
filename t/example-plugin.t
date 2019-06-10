use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_args({i = 1, s = "s", t = {1}})
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



=== TEST 2: missing args
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")

            local ok, err = plugin.check_args({s = "s", t = {1}})
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



=== TEST 3: small then minimum
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_args({i = -1, s = "s", t = {1, 2}})
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



=== TEST 4: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_args({i = 1, s = 123, t = {1}})
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



=== TEST 5: the size of array < minItems
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.example-plugin")
            local ok, err = plugin.check_args({i = 1, s = '123', t = {}})
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
plugins:
  - example-plugin
  - not-exist-plugin
--- error_log
failed to load plugin not-exist-plugin err: module 'apisix.plugins.not-exist-plugin' not found
rewrite(): plugin rewrite phase



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
                    plugin_config = {
                        ["example-plugin"] = {i = 1, s = "s", t = {1, 2}},
                        ["new-plugin"] = {a = "a"},
                    }
                },
                modifiedIndex = 1,
            }, all_plugins)

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
