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

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("no_error_log", "[error]");

    $block;
});

no_long_string();
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: ensure all plugins have exposed their name
--- stream_enable
--- stream_server_config
    content_by_lua_block {
        local lfs = require("lfs")
        for file_name in lfs.dir(ngx.config.prefix() .. "/../../apisix/stream/plugins/") do
            if string.match(file_name, ".lua$") then
                local expected = file_name:sub(1, #file_name - 4)
                local plugin = require("apisix.stream.plugins." .. expected)
                if plugin.name ~= expected then
                    ngx.say("expected ", expected, " got ", plugin.name)
                    return
                end
            end
        end
        ngx.say('ok')
    }
--- stream_response
ok
