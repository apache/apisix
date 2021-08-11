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
    enable_compression: true
_EOC_

    $block->set_value("yaml_config", $user_yaml_config);
    $block->set_value("request", "GET /t");
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
--- no_error_log
[error]



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
--- no_error_log
[error]
--- error_log
start xxxxxx
