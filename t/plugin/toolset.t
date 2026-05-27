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

=== TEST 1: check if toolset plugin sync function is run every second
--- error_code: 404
--- wait: 1
--- grep_error_log eval
qr/syncing toolset plugin/
--- grep_error_log_out
syncing toolset plugin
syncing toolset plugin



=== TEST 2: reload with empty config for a sub-plugin(table-count)
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
  table_count = {}
}
]]

            -- Write the new contents to the file
            write_file(module_path, new_config)

            ngx.sleep(2)

            -- Restore the old contents to the file
            write_file(module_path, old_config)

            ngx.sleep(2)

        }
    }
--- grep_error_log eval
qr/empty config found for table_count.Running with default values/
--- grep_error_log_out
empty config found for table_count.Running with default values
empty config found for table_count.Running with default values



=== TEST 3: reload with different config for table-count (remove scopes)
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
    lua_modules = { "t.table-count-example" }, -- change it
    interval = 5,
    depth = 10, -- when it is not passed, default depth will be 1
    -- optional, default is all APISIX processes
    scopes = {}
  }
}
]]

            -- Write the new contents to the file
            write_file(module_path, new_config)

            ngx.sleep(2)

            -- Restore the old contents to the file
            write_file(module_path, old_config)

            ngx.sleep(2)

        }
    }
--- grep_error_log eval
qr/config changed. reloading plugin:/
--- grep_error_log_out eval
qr/(?:config changed\. reloading plugin:\s*){2,}/



=== TEST 4: reload with empty toolset config
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
]]

            -- Write the new contents to the file
            write_file(module_path, new_config)

            ngx.sleep(2)

            -- Restore the old contents to the file
            write_file(module_path, old_config)

            ngx.sleep(2)

        }
    }
--- grep_error_log eval
qr/empty plugin config file/
--- grep_error_log_out eval
qr/(?:empty plugin config file\s*){1,}/
