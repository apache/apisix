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

    my $extra_yaml_config = <<_EOC_;
plugins:                          # plugin list
  - log-rotate
  - serverless-post-function

nginx_config:
  error_log_level: info
  http:
    access_log_buffer: 1

plugin_attr:
  log-rotate:
    interval: 1
    max_kept: 3
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);


    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

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

            if not has_split_access_file or not has_split_error_file then
               ngx.status = 500
            else
               ngx.status = 200
            end
        }
    }
--- error_code eval
[200]



=== TEST 2: in current log
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.1)
            ngx.log(ngx.WARN, "start xxxxxx")
            ngx.say("done")
        }
    }
--- response_body
done
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

            ngx.sleep(2.1) -- make sure two files will be rotated out if we don't disable it

            local n_split_error_file = 0
            local lfs = require("lfs")
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "__error.log$") then
                    n_split_error_file = n_split_error_file + 1
                end
            end

            -- Before hot reload, the log rotate may or may not take effect.
            -- It depends on the time we start the test
            ngx.say(n_split_error_file <= 1)
        }
    }
--- response_body
done
true



=== TEST 5: check file changes (disable compression)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(2)

            local default_logs = {}
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "__error.log$") or string.match(file_name, "__access.log$") then
                    local filepath = ngx.config.prefix() .. "/logs/" .. file_name
                    local attr = lfs.attributes(filepath)
                    if attr then
                        default_logs[filepath] = { change = attr.change, size = attr.size }
                    end
                end
            end

            ngx.sleep(1)

            local passed = false
            for filepath, origin_attr in pairs(default_logs) do
                local check_attr = lfs.attributes(filepath)
                if check_attr.change == origin_attr.change and check_attr.size == origin_attr.size then
                    passed = true
                else
                    passed = false
                    break
                end
            end

            if passed then
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 6: reopen plugin and access logs even if one configured log file is missing
# Log-phase plugins run after the response is sent to the client. Keep the
# rotation setup, request trigger, and assertions in separate requests so the
# previous request's log-phase output is flushed before checking the log files.
--- timeout: 30
--- config
    location /setup {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local prefix = ngx.config.prefix()
            local access_log = prefix .. "/logs/access.log"
            local function fail(msg)
                ngx.status = 500
                ngx.say(msg)
                ngx.exit(ngx.HTTP_OK)
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-post-function": {
                            "phase": "log",
                            "functions" : ["return function(conf, ctx) require('apisix.core').log.info('serverless post-rotation marker') end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                fail(body)
            end

            os.remove(access_log)

            ngx.sleep(2.5)

            local data = [[
apisix:
  node_listen: 1984
  admin_key: null
plugins:
  - serverless-post-function
nginx_config:
  error_log_level: info
  http:
    access_log_buffer: 1
            ]]
            require("lib.test_admin").set_config_yaml(data)
            code, _, body = t('/apisix/admin/plugins/reload',
                              ngx.HTTP_PUT)
            if code >= 300 then
                fail(body)
            end

            ngx.say("passed")
        }
    }
    location /verify {
        content_by_lua_block {
            local prefix = ngx.config.prefix()
            local access_log = prefix .. "/logs/access.log"
            local error_log = prefix .. "/logs/error.log"
            local marker = "serverless post-rotation marker"
            local function fail(msg)
                ngx.status = 500
                ngx.say(msg)
                ngx.exit(ngx.HTTP_OK)
            end

            ngx.sleep(0.5)

            local f, err = io.open(error_log, "r")
            if not f then
                fail("failed to open current error log: " .. err)
            end
            local error_content = f:read("*all")
            f:close()

            f, err = io.open(access_log, "r")
            if not f then
                fail("failed to open current access log: " .. err)
            end
            local access_content = f:read("*all")
            f:close()

            if not string.find(error_content, marker, 1, true) then
                fail("current error log missed post-rotation plugin log")
            end

            if not string.find(access_content, "GET /hello", 1, true) then
                fail("current access log missed post-rotation request")
            end

            ngx.say("passed")
        }
    }
--- pipelined_requests eval
["GET /setup", "GET /hello", "GET /verify"]
--- error_code eval
[200, 200, 200]
--- response_body eval
["passed\n", "hello world\n", "passed\n"]
