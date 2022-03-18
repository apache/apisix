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

    if (!defined $block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  admin_key: ~
plugins:
  - log-rotate
plugin_attr:
  log-rotate:
    interval: 1
    max_kept: 3
    enable_compression: true
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests;

__DATA__

=== TEST 1: log rotate, with enable log file compression
--- config
    location /t {
        content_by_lua_block {
            ngx.log(ngx.ERR, "start xxxxxx")
            ngx.sleep(2.5)
            local has_split_access_file = false
            local has_split_error_file = false
            local lfs = require("lfs")
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "__access.log.tar.gz$") then
                    has_split_access_file = true
                end

                if string.match(file_name, "__error.log.tar.gz$") then
                    has_split_error_file = true
                end
            end

            if not has_split_access_file or not has_split_error_file then
               ngx.status = 500
            else
               ngx.status = 200
            end
        }
    }



=== TEST 2: in current log, with enable log file compression
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



=== TEST 3: check file changes (enable compression)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(2)

            local default_logs = {}
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "__error.log.tar.gz$") or string.match(file_name, "__access.log.tar.gz$") then
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



=== TEST 4: test rotate time align
--- yaml_config
apisix:
  node_listen: 1984
  admin_key: ~
plugins:
  - log-rotate
plugin_attr:
  log-rotate:
    interval: 3600
    max_kept: 1
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.1)
            local log_file = ngx.config.prefix() .. "logs/error.log"
            local file = io.open(log_file, "r")
            local log = file:read("*a")

            local m, err = ngx.re.match(log, [[first init rotate time is: (\d+)]], "jom")
            if not m then
                ngx.log(ngx.ERR, "failed to gmatch: ", err)
                return
            end

            ngx.sleep(2)

            local now_time = ngx.time()
            local interval = 3600
            local rotate_time = now_time + interval - (now_time % interval)
            if tonumber(m[1]) == tonumber(rotate_time) then
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
