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

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: xds
    enable_admin: false
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests;

__DATA__

=== TEST 1: proxy request using data written by xds
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, { method = "GET"})

            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- response_body
hello world
