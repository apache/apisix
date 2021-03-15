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

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  admin_key: null

plugins:                          # plugin list
  - log-rotate

plugin_attr:
  log-rotate:
    interval: 1
    max_kept: 3
_EOC_

    $block->set_value("yaml_config", $user_yaml_config);
    $block->set_value("request", "GET /t");
});

run_tests;

__DATA__

=== TEST 1: log rotate
--- config
    location /t {
        content_by_lua_block {
            ngx.log(ngx.ERR, "start xxxxxx")
            ngx.sleep(2.5)
            local has_split_access_file = false
            local has_split_error_file = false
            local lfs = require("lfs")
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "__access.log$") then
                    has_split_access_file = true
                end

                if string.match(file_name, "__error.log$") then
                    local f = assert(io.open(ngx.config.prefix() .. "/logs/" .. file_name, "r"))
                    local content = f:read("*all")
                    f:close()
                    local index = string.find(content, "start xxxxxx")
                    if index then
                        has_split_error_file = true
                    end
                end
            end

            if not has_split_error_file or not has_split_error_file then
               ngx.status = 500
            else
               ngx.status = 200
            end
        }
    }
--- error_code eval
[200]
--- no_error_log
[error]



=== TEST 2: in current log
--- config
    location /t {
        content_by_lua_block {
            ngx.log(ngx.WARN, "start xxxxxx")
            ngx.sleep(0.1)
            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
[error]
--- error_log
start xxxxxx



=== TEST 3: fix: ensure only one timer is running
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local t = require("lib.test_admin").test
            local code, _, org_body = t('/apisix/admin/plugins/reload',
                                        ngx.HTTP_PUT)

            ngx.status = code
            ngx.say(org_body)

            ngx.sleep(1)

            local lfs = require("lfs")
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "__error.log$") then
                    local f = assert(io.open(ngx.config.prefix() .. "/logs/" .. file_name, "r"))
                    local content = f:read("*all")
                    f:close()
                    local counter = 0
                    ngx.re.gsub(content, [=[run timer\[plugin#log-rotate\]]=], function()
                        counter = counter + 1
                        return ""
                    end)

                    if counter ~= 1 then
                        ngx.say("not a single rotator run at the same time: ", file_name)
                    end
                end
            end
        }
    }
--- response_body
done
--- no_error_log
[error]



=== TEST 4: disable log-rotate via hot reload
--- config
    location /t {
        content_by_lua_block {
            local data = [[
apisix:
  node_listen: 1984
  admin_key: null
plugins:
  - prometheus
            ]]
            require("lib.test_admin").set_config_yaml(data)
            local t = require("lib.test_admin").test
            local code, _, org_body = t('/apisix/admin/plugins/reload',
                                        ngx.HTTP_PUT)

            ngx.status = code
            ngx.say(org_body)

            ngx.sleep(1.5)

            local n_split_error_file = 0
            local lfs = require("lfs")
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "__error.log$") then
                    n_split_error_file = n_split_error_file + 1
                end
            end

            ngx.say(n_split_error_file)
        }
    }
--- response_body
done
1
--- no_error_log
[error]
