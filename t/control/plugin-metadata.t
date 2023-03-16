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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests;

__DATA__

=== TEST 1: add plugin metadatas
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/plugin_metadata/example-plugin',
                ngx.HTTP_PUT,
                [[{
                    "skey": "val",
                    "ikey": 1
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            local code = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[
                {"log_format": {"upstream_response_time": "$upstream_response_time"}}
                ]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end
        }
    }
--- error_code: 200



=== TEST 2: dump all plugin metadatas
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, _, res = t('/v1/plugin_metadatas', ngx.HTTP_GET)
            local json = require("toolkit.json")
            res = json.decode(res)
            for _, metadata in ipairs(res) do
                if metadata.id == "file-logger" then
                    ngx.say("check log_format: ", metadata.log_format.upstream_response_time == "$upstream_response_time")
                elseif metadata.id == "example-plugin" then
                    ngx.say("check skey: ", metadata.skey == "val")
                    ngx.say("check ikey: ", metadata.ikey == 1)
                end
            end
        }
    }
--- response_body
check log_format: true
check skey: true
check ikey: true



=== TEST 3: dump file-logger metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local _, _, res = t('/v1/plugin_metadata/file-logger', ngx.HTTP_GET)
            local json = require("toolkit.json")
            metadata = json.decode(res)
            if metadata.id == "file-logger" then
                ngx.say("check log_format: ", metadata.log_format.upstream_response_time == "$upstream_response_time")
            end
        }
    }
--- response_body
check log_format: true



=== TEST 4: plugin without metadata
--- request
GET /v1/plugin_metadata/batch-requests
--- error_code: 404
--- response_body
{"error_msg":"plugin metadata[batch-requests] not found"}
