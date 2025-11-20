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
no_root_location();

run_tests;

__DATA__

=== TEST 1: Check extra_lua_path via block definition
Verify that extra_lua_path block definition adds path to lua_package_path
--- extra_lua_path: /test/custom/path/?.lua
--- config
    location /t {
        content_by_lua_block {
            local path = package.path
            if string.find(path, "/test/custom/path/?.lua", 1, true) then
                ngx.say("FOUND: extra_lua_path is in package.path")
            else
                ngx.say("NOT FOUND: extra_lua_path is missing")
                ngx.say("package.path: ", path)
            end
        }
    }
--- request
GET /t
--- response_body
FOUND: extra_lua_path is in package.path



=== TEST 2: Check extra_lua_cpath via block definition
Verify that extra_lua_cpath block definition adds path to lua_package_cpath
--- extra_lua_cpath: /test/custom/path/?.so
--- config
    location /t {
        content_by_lua_block {
            local cpath = package.cpath
            if string.find(cpath, "/test/custom/path/?.so", 1, true) then
                ngx.say("FOUND: extra_lua_cpath is in package.cpath")
            else
                ngx.say("NOT FOUND: extra_lua_cpath is missing")
                ngx.say("package.cpath: ", cpath)
            end
        }
    }
--- request
GET /t
--- response_body
FOUND: extra_lua_cpath is in package.cpath



=== TEST 3: Check extra_lua_path from extra_yaml_config
Verify that extra_lua_path is parsed from extra_yaml_config
--- extra_yaml_config
apisix:
  extra_lua_path: "/yaml/custom/path/?.lua"
--- config
    location /t {
        content_by_lua_block {
            local path = package.path
            if string.find(path, "/yaml/custom/path/?.lua", 1, true) then
                ngx.say("FOUND: extra_lua_path from yaml config is in package.path")
            else
                ngx.say("NOT FOUND: extra_lua_path from yaml config is missing")
                ngx.say("package.path: ", path)
            end
        }
    }
--- request
GET /t
--- response_body
FOUND: extra_lua_path from yaml config is in package.path



=== TEST 4: Check extra_lua_cpath from extra_yaml_config
Verify that extra_lua_cpath is parsed from extra_yaml_config
--- extra_yaml_config
apisix:
  extra_lua_cpath: "/yaml/custom/path/?.so"
--- config
    location /t {
        content_by_lua_block {
            local cpath = package.cpath
            if string.find(cpath, "/yaml/custom/path/?.so", 1, true) then
                ngx.say("FOUND: extra_lua_cpath from yaml config is in package.cpath")
            else
                ngx.say("NOT FOUND: extra_lua_cpath from yaml config is missing")
                ngx.say("package.cpath: ", cpath)
            end
        }
    }
--- request
GET /t
--- response_body
FOUND: extra_lua_cpath from yaml config is in package.cpath



=== TEST 5: Check both extra_lua_path and extra_lua_cpath
Verify that both paths can be set simultaneously
--- extra_lua_path: /test/lua/?.lua
--- extra_lua_cpath: /test/so/?.so
--- config
    location /t {
        content_by_lua_block {
            local path = package.path
            local cpath = package.cpath
            local lua_found = string.find(path, "/test/lua/?.lua", 1, true)
            local so_found = string.find(cpath, "/test/so/?.so", 1, true)

            if lua_found and so_found then
                ngx.say("FOUND: both extra_lua_path and extra_lua_cpath")
            else
                ngx.say("NOT FOUND")
                ngx.say("lua_path found: ", lua_found and "yes" or "no")
                ngx.say("so_path found: ", so_found and "yes" or "no")
            end
        }
    }
--- request
GET /t
--- response_body
FOUND: both extra_lua_path and extra_lua_cpath



=== TEST 6: Check path is prepended (comes first)
Verify that extra_lua_path is at the beginning of package.path
--- extra_lua_path: /first/path/?.lua
--- config
    location /t {
        content_by_lua_block {
            local path = package.path
            -- Check if custom path appears before apisix_home
            local custom_pos = string.find(path, "/first/path/?.lua", 1, true)
            local apisix_pos = string.find(path, "/apisix/?.lua", 1, true)

            if custom_pos and apisix_pos and custom_pos < apisix_pos then
                ngx.say("SUCCESS: extra_lua_path is prepended correctly")
            else
                ngx.say("FAIL: extra_lua_path is not at the beginning")
                ngx.say("custom_pos: ", custom_pos or "nil")
                ngx.say("apisix_pos: ", apisix_pos or "nil")
            end
        }
    }
--- request
GET /t
--- response_body
SUCCESS: extra_lua_path is prepended correctly



=== TEST 7: Block definition takes precedence over yaml_config
Verify that block definition is used when both are provided
--- extra_lua_path: /block/path/?.lua
--- extra_yaml_config
apisix:
  extra_lua_path: "/yaml/path/?.lua"
--- config
    location /t {
        content_by_lua_block {
            local path = package.path
            local block_found = string.find(path, "/block/path/?.lua", 1, true)
            local yaml_found = string.find(path, "/yaml/path/?.lua", 1, true)

            if block_found and not yaml_found then
                ngx.say("SUCCESS: block definition takes precedence")
            elseif yaml_found and not block_found then
                ngx.say("FAIL: yaml config was used instead of block")
            elseif block_found and yaml_found then
                ngx.say("UNEXPECTED: both paths found")
            else
                ngx.say("FAIL: neither path found")
            end
        }
    }
--- request
GET /t
--- response_body
SUCCESS: block definition takes precedence
