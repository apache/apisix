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

log_level('warn');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: simple hook in route
--- yaml_config
plugin_attr:
  inspect:
    delay: 1
    hooks_file: "/tmp/apisix_inspect_hooks.lua"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/inspect',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/inspect",
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : ["return function() assert(require(\"lib.test_inspect\").run1() == \"hello\"); ngx.say(\"ok\"); end"]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                 }]])

            if code >= 300 then
                ngx.status = code
                return
            end

            local file = io.open("/tmp/apisix_inspect_hooks.lua", "w")
            file:write([[
            local dbg = require "apisix.inspect.dbg"

            dbg.set_hook("t/lib/test_inspect.lua", 21, nil, function(info)
                ngx.log(ngx.WARN, "var1=", info.vals.var1)
                return true
            end)
            ]])
            file:close()

            ngx.sleep(2)

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/inspect"

            local httpc = http.new()
            local res = httpc:request_uri(uri, {method = "GET"})
            assert(res.body == "ok\n")

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- timeout: 5
--- error_log
var1=hello
--- no_error_log
[error]
