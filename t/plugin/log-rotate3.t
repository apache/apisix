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

    if (!defined $block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
plugins:
  - log-rotate
plugin_attr:
  log-rotate:
    interval: 86400
    max_size: 9
    max_kept: 3
    enable_compression: false
_EOC_

        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests;

__DATA__

=== TEST 1: log rotate by max_size
--- config
    location /t {
        content_by_lua_block {
            ngx.log(ngx.ERR, "start xxxxxx")
            ngx.sleep(2)
            local has_split_access_file = false
            local has_split_error_file = false
            local lfs = require("lfs")
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "__access.log$") then
                    has_split_access_file = true
                end

                if string.match(file_name, "__error.log$") then
                    has_split_error_file = true
                end
            end

            if not has_split_access_file and has_split_error_file then
               ngx.status = 200
            else
               ngx.status = 500
            end
        }
    }



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



=== TEST 3: check file changes
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)

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



=== TEST 4: max_kept effective on differently named compression files
--- extra_yaml_config
plugins:
  - log-rotate
plugin_attr:
  log-rotate:
    interval: 1
    max_kept: 1
    enable_compression: true
--- yaml_config
nginx_config:
    error_log: logs/err1.log
    http:
        access_log: logs/acc1.log
--- config
    location /t {
        error_log logs/err1.log info;
        access_log logs/acc1.log;

        content_by_lua_block {
            ngx.sleep(3)
            local lfs = require("lfs")
            local count = 0
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, ".tar.gz$") then
                    count = count + 1
                end
            end
            --- only two compression file
            ngx.say(count)
        }
    }
--- response_body
2



=== TEST 5: check whether new log files were created
--- extra_yaml_config
plugins:
  - log-rotate
plugin_attr:
  log-rotate:
    interval: 1
    max_kept: 0
    enable_compression: false
--- yaml_config
nginx_config:
    error_log: logs/err2.log
    http:
        access_log: logs/acc2.log
--- config
    location /t {
        error_log logs/err2.log info;
        access_log logs/acc2.log;

        content_by_lua_block {
            ngx.sleep(3)
            local lfs = require("lfs")
            local count = 0
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "err2.log$") or string.match(file_name, "acc2.log$") then
                    count = count + 1
                end
            end
            ngx.say(count)
        }
    }
--- response_body
2



=== TEST 6: rotate do not work for access log when enable_access_log is set to false
--- extra_yaml_config
plugins:
  - log-rotate
plugin_attr:
  log-rotate:
    interval: 1
    max_kept: 1
    enable_compresssion: false
--- yaml_config
nginx_config:
    http:
        enable_access_log: false
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(3)
            local lfs = require("lfs")
            local access_count, error_count = 0, 0
            for file_name in lfs.dir(ngx.config.prefix() .. "/logs/") do
                if string.match(file_name, "error.log$") then
                    error_count = error_count + 1
                end
                if string.match(file_name, "access.log$") then
                    access_count = access_count + 1
                end
            end
            ngx.say(access_count)
            ngx.say(error_count)
        }
    }
--- response_body
0
2
