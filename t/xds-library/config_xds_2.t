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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
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

=== TEST 1: proxy request using data written by xds(id = 1)
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



=== TEST 2: proxy request using data written by xds(id = 2, upstream_id = 1)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, { method = "GET"})

            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- response_body
hello1 world



=== TEST 3: proxy request using data written by xds(id = 3, upstream_id = 2)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1.5)
            local core = require("apisix.core")
            local value = ngx.shared["xds-config"]:flush_all()
            ngx.sleep(1.5)
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



=== TEST 4: flush all keys in xds config
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.shared["xds-config"]:flush_all()
            ngx.update_time()
            ngx.shared["xds-config-version"]:set("version", ngx.now())
            ngx.sleep(1.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, { method = "GET"})

            if not res then
                ngx.say(err)
                return
            end
            ngx.status = res.status
            ngx.print(res.body)
        }
    }
--- error_code: 404
--- response_body
{"error_msg":"404 Route Not Found"}



=== TEST 5: bad format json
--- config
    location /t {
        content_by_lua_block {
            local data = [[{
                upstream = {
                    type = "roundrobin"
                    nodes = {
                        ["127.0.0.1:1980"] = 1,
                    }
                },
                uri = "/bad_json"
            }]]
            ngx.shared["xds-config"]:set("/routes/3", data)
            ngx.update_time()
            ngx.shared["xds-config-version"]:set("version", ngx.now())
            ngx.sleep(1.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/bad_json"
            local res, err = httpc:request_uri(uri, { method = "GET"})

            if not res then
                ngx.say(err)
                return
            end
            ngx.status = res.status
        }
    }
--- wait: 2
--- error_code: 404
--- error_log
decode the conf of [/routes/3] failed, err: Expected object key string but found invalid token



=== TEST 6: schema check fail
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local data = {
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:65536"] = 1,
                    }
                }
            }
            local data_str = core.json.encode(data)
            ngx.shared["xds-config"]:set("/routes/3", data_str)
            ngx.update_time()
            ngx.shared["xds-config-version"]:set("version", ngx.now())
            ngx.sleep(1.5)
        }
    }
--- no_error_log
[alert]
-- wait: 2
--- error_log
failed to check the conf of [/routes/3] err:allOf 1 failed: value should match only one schema, but matches none



=== TEST 7: not table
--- config
    location /t {
        content_by_lua_block {
            local data = "/not_table"
            ngx.shared["xds-config"]:set("/routes/3", data)
            ngx.update_time()
            ngx.shared["xds-config-version"]:set("version", ngx.now())
            ngx.sleep(1.5)
        }
    }
--- no_error_log
[alert]
-- wait: 2
--- error_log
invalid conf of [/routes/3], conf: nil, it should be an object
