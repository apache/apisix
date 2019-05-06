use t::APIMeta 'no_plan';

repeat_each(2);
no_long_string();
log_level('info');

run_tests;

__DATA__

=== TEST 1: check arguments
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
failed to check args: args.i expect int value but got: [nil]
failed to check args: args.s expect string value but got: [3]
failed to check args: args.t expect table value but got: []
done



=== TEST 2: load plugins
--- config
    location /t {
        content_by_lua_block {
            local plugins, err = require("apimeta.plugin").load()
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
plugin name: example_plugin priority: 1000
--- error_log
failed to load plugin not_exist_plugin err: module 'apimeta.plugins.not_exist_plugin' not found
rewrite(): plugin rewrite phase



=== TEST 3: filter plugins
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apimeta.plugin")

            local all_plugins, err = plugin.load()
            if not all_plugins then
                ngx.say("failed to load plugins: ", err)
            end

            local filter_plugins = plugin.filter_plugin({
                example_plugin = {i = 1, s = "s", t = {1, 2}},
                new_plugin = {a = "a"},
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
plugin [example_plugin] config: {"i":1,"s":"s","t":[1,2]}
