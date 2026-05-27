use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

my $user_yaml_config = <<_EOC_;
plugins:
  - toolset
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: load the test table and check table count
--- extra_init_by_lua
            local lfs = require("lfs")
            -- Define the path to the Lua module
            local module_path = "./apisix/plugins/toolset/config.lua"

            -- Function to read the contents of a file
            local function read_file(path)
                local file = io.open(path, "r")
                if not file then return nil end
                local content = file:read("*a")
                file:close()
                return content
            end

            -- Function to write contents to a file
            local function write_file(path, content)
                local file = io.open(path, "w")
                if not file then return nil end
                file:write(content)
                file:close()
            end

            -- Load the module and save its contents as "old_config"
            local old_config = read_file(module_path)

            -- Check if the module was read successfully
            if not old_config then
                error("Failed to read the module file.")
            end

            -- Define the new multiline string to be inserted into the file
            local new_config =
[[
return {
  table_count = {lua_modules = {"t.table-count-example"}, interval = 1}
}
]]

            -- Write the new contents to the file
            write_file(module_path, new_config)
            local example = require("t.table-count-example")
            example.test()
--- wait: 2
--- error_code: 404
--- grep_error_log eval
qr/package t.table-count-example table count is: 4/
--- grep_error_log_out
package t.table-count-example table count is: 4
package t.table-count-example table count is: 4



=== TEST 2: load the test table and check table count for circular reference
--- extra_init_by_lua
            local lfs = require("lfs")
            -- Define the path to the Lua module
            local module_path = "./apisix/plugins/toolset/config.lua"

            -- Function to read the contents of a file
            local function read_file(path)
                local file = io.open(path, "r")
                if not file then return nil end
                local content = file:read("*a")
                file:close()
                return content
            end

            -- Function to write contents to a file
            local function write_file(path, content)
                local file = io.open(path, "w")
                if not file then return nil end
                file:write(content)
                file:close()
            end

            -- Load the module and save its contents as "old_config"
            local old_config = read_file(module_path)

            -- Check if the module was read successfully
            if not old_config then
                error("Failed to read the module file.")
            end

            -- Define the new multiline string to be inserted into the file
            local new_config =
[[
return {
  table_count = {lua_modules = {"t.table-count-example"}, interval = 1,depth = 10}
}
]]

            -- Write the new contents to the file
            write_file(module_path, new_config)
            local example = require("t.table-count-example")
            example.test_circular()
--- wait: 2
--- error_code: 404
--- grep_error_log eval
qr/package t.table-count-example table count is: 8/
--- grep_error_log_out
package t.table-count-example table count is: 8
package t.table-count-example table count is: 8



=== TEST 3: check enforced depth limit
--- extra_init_by_lua
            local lfs = require("lfs")
            -- Define the path to the Lua module
            local module_path = "./apisix/plugins/toolset/config.lua"

            -- Function to read the contents of a file
            local function read_file(path)
                local file = io.open(path, "r")
                if not file then return nil end
                local content = file:read("*a")
                file:close()
                return content
            end

            -- Function to write contents to a file
            local function write_file(path, content)
                local file = io.open(path, "w")
                if not file then return nil end
                file:write(content)
                file:close()
            end

            -- Load the module and save its contents as "old_config"
            local old_config = read_file(module_path)

            -- Check if the module was read successfully
            if not old_config then
                error("Failed to read the module file.")
            end

            -- Define the new multiline string to be inserted into the file
            local new_config =
[[
return {
  table_count = {lua_modules = {"t.table-count-example"}, interval = 1}
}
]]

            -- Write the new contents to the file
            write_file(module_path, new_config)
            local example = require("t.table-count-example")
            example.test_depth_more_than_10()
--- error_code: 404
--- wait: 2
--- grep_error_log eval
qr/out of depth..skipping count/
--- grep_error_log_out
out of depth..skipping count
out of depth..skipping count



=== TEST 4: reload the config with no lua modules
--- config
    location /t {
        content_by_lua_block {
            local lfs = require("lfs")

            -- Define the path to the Lua module
            local module_path = "./apisix/plugins/toolset/config.lua"

            -- Function to read the contents of a file
            local function read_file(path)
                local file = io.open(path, "r")
                if not file then return nil end
                local content = file:read("*a")
                file:close()
                return content
            end

            -- Function to write contents to a file
            local function write_file(path, content)
                local file = io.open(path, "w")
                if not file then return nil end
                file:write(content)
                file:close()
            end

            -- Load the module and save its contents as "old_config"
            local old_config = read_file(module_path)

            -- Check if the module was read successfully
            if not old_config then
                error("Failed to read the module file.")
            end

            -- Define the new multiline string to be inserted into the file
            local new_config =
[[
return {
    table_count = {
        lua_modules = {}, -- change it
        interval = 5,
        depth = 10, -- when it is not passed, default depth will be 1
        -- optional, default is all APISIX processes
        scopes = {"worker", "privileged agent"}
    }
}

]]

            -- Write the new contents to the file
            write_file(module_path, new_config)

            ngx.sleep(2)

            -- Restore the old contents to the file
            write_file(module_path, old_config)

        }
    }
--- wait: 2
--- grep_error_log eval
qr/no lua_modules provided for table count/
--- grep_error_log_out
no lua_modules provided for table count
no lua_modules provided for table count
