#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

use Cwd qw(cwd);
my $apisix_home = $ENV{APISIX_HOME} || cwd();

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $lua_deps_path = $block->lua_deps_path // <<_EOC_;
        lua_package_path "$apisix_home/?.lua;$apisix_home/?/init.lua;$apisix_home/deps/share/lua/5.1/?/init.lua;$apisix_home/deps/share/lua/5.1/?.lua;$apisix_home/apisix/?.lua;$apisix_home/t/?.lua;;";
        lua_package_cpath "$apisix_home/?.so;$apisix_home/t/xds-library/?.so;$apisix_home/deps/lib/lua/5.1/?.so;$apisix_home/deps/lib64/lua/5.1/?.so;;";
_EOC_

    $block->set_value("lua_deps_path", $lua_deps_path);

    my $extra_init_by_lua = <<_EOC_;
    --
    local config_xds = require("apisix.core.config_xds")

    local inject = function(mod, name)
        local old_f = mod[name]
        mod[name] = function (...)
            ngx.log(ngx.WARN, "config_xds run ", name)
            return { true }
        end
    end

    inject(config_xds, "new")

_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: xds
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests;

__DATA__

=== TEST 1: load xDS library successfully
--- config
    location /t {
        content_by_lua_block {
            ngx.say("ok")
        }
    }
--- no_error_log eval
qr/can not load xDS library/



=== TEST 2: read data form shdict that wirted by xDS library
--- config
    location /t {
        content_by_lua_block {
            -- wait for xds library sync data
            ngx.sleep(1.5)
            local core = require("apisix.core")
            local value = ngx.shared["xds-config"]:get("/routes/1")
            local route_conf, err = core.json.decode(value)
            local json_encode = require("toolkit.json").encode
            ngx.say(json_encode(route_conf.uri))
        }
    }
--- response_body
"/hello"



=== TEST 3: read conf version
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local version
            for i = 1, 5 do
                version = ngx.shared["xds-config-version"]:get("version")
                if version then
                    ngx.say(version)
                    break
                end
                -- wait for xds library sync data
                ngx.sleep(1.5)
            end
        }
    }
--- response_body eval
qr/^\d{13}$/
