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

no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: set route(host + uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "script": "local core   = require(\"apisix.core\")\nlocal pairs  = pairs\nlocal type   = type\nlocal ngx    = ngx\nlocal plugin = require(\"apisix.plugin\")\n\n\nlocal _M = {\n    version = 0.1,\n    priority = 412,\n    conf = {\n        [\"limit-count_1\"] = {\n            count = 2,\n            time_window = 60,\n            rejected_code = 503,\n            key = \"remote_addr\"\n        },\n        [\"response-rewrite_1\"] = {\n            body = {\n                code = \"ok\",\n                message = \"new json body\"\n            },\n            headers = {\n                [\"X-limit-status\"] = 1\n            }\n        },\n        [\"response-rewrite_2\"] = {\n            body = {\n                code = \"ok\",\n                message = \"new json body2\"\n            },\n            headers = {\n                [\"X-limit-status\"] = 2\n            }\n        }\n    },\n    plugins = {},\n}\n\n\nfunction _M.access(api_ctx)\n    -- 1\n    local limit_count = plugin.get(\"limit-count\")\n    local condition_fun1 = limit_count[\"access\"] and limit_count[\"access\"] or limit_count[\"rewrite\"]\n    -- 2\n    local response_rewrite = plugin.get(\"response-rewrite\")\n    local condition_fun2 = response_rewrite[\"access\"] and response_rewrite[\"access\"] or response_rewrite[\"rewrite\"]\n\n    core.log.error(\"test access\")\n\n    local code, body = nil, nil\n    if condition_fun1 then\n        code, body = condition_fun1(_M.conf[\"limit-count_1\"], api_ctx)\n    end\n\n    core.log.error(\"test access2\")\n\n    -- save ordered plugins\n    core.table.insert(_M.plugins, \"limit-count\")\n    core.table.insert(_M.plugins, \"limit-count_1\")\n\n    if code == 503 then\n        core.log.error(\"test access3\")\n        if condition_fun2 then\n            core.log.error(\"test access33\")\n            condition_fun2(_M.conf[\"response-rewrite_1\"], api_ctx)\n        end\n        -- save ordered plugins\n        core.table.insert(_M.plugins, \"response-rewrite\")\n        core.table.insert(_M.plugins, \"response-rewrite_1\")\n    else\n        core.log.error(\"test access4\")\n        if condition_fun2 then\n            core.log.error(\"test access44\")\n            condition_fun2(_M.conf[\"response-rewrite_2\"], api_ctx)\n        end\n        -- save ordered plugins\n        core.table.insert(_M.plugins, \"response-rewrite\")\n        core.table.insert(_M.plugins, \"response-rewrite_2\")\n        core.log.error(\"test access5\")\n    end\n\nend\n\n\nfunction _M.header_filter(ctx)\n    local plugin_count = #_M.plugins\n    core.log.error(\"test header filter plugin count: \", plugin_count)\n    for i = 1, plugin_count, 2 do\n        core.log.error(\"header i:\", i)\n        core.log.error(\"header i + 1:\", i + 1)\n        local plugin_name = _M.plugins[i]\n        local plugin_conf_name = _M.plugins[i + 1]\n        core.log.error(\"test header filter plugin_name: \", plugin_name)\n        core.log.error(\"test header filter plugin_conf_name: \", plugin_conf_name)\n        local plugin_obj = plugin.get(plugin_name)\n        core.log.error(\"test header filter plugin_obj: \", core.json.delay_encode(plugin_obj, true))\n        local phase_fun = plugin_obj[\"header_filter\"]\n        core.log.error(\"test header phase_fun: \", core.json.delay_encode(phase_fun, true))\n        if phase_fun then\n            core.log.error(\"test header filter\")\n            local code, body = phase_fun(_M.conf[plugin_conf_name], api_ctx)\n            if code or body then\n                -- do we exit here?\n                core.log.error(\"test header filter2\")\n                core.response.exit(code, body)\n            end\n        end\n    end\nend\n\n\nfunction _M.body_filter(ctx)\n    core.log.error(\"test body filter plugin count: \", #_M.plugins)\n    for i = 1, #_M.plugins, 2 do\n        local plugin_name = _M.plugins[i]\n        local plugin_conf_name = _M.plugins[i + 1]\n\n        local plugin_obj = plugin.get(plugin_name)\n        local phase_fun = plugin_obj[\"body_filter\"]\n\n        core.log.error(\"test body filter plugin_name: \", plugin_name)\n        core.log.error(\"test body filter plugin_conf_name: \", plugin_conf_name)\n        core.log.error(\"test body filter plugin_obj: \", core.json.delay_encode(plugin_obj, true))\n\n        if phase_fun then\n            core.log.error(\"test body filter\")\n            local code, body = phase_fun(_M.conf[plugin_conf_name], api_ctx)\n            if code or body then\n                -- do we exit here?\n                core.log.error(\"test body filter2\")\n                core.response.exit(code, body)\n            end\n        end\n    end\nend\n\n\nfunction _M.log(ctx)\n    for i = 1, #_M.plugins, 2 do\n        local plugin_name = _M.plugins[i]\n        local plugin_conf_name = _M.plugins[i + 1]\n\n        local plugin_obj = plugin.get(plugin_name)\n        local phase_fun = plugin_obj[\"log\"]\n        if phase_fun then\n            local code, body = phase_fun(_M.conf[plugin_conf_name], api_ctx)\n            if code or body then\n                -- do we exit here?\n                core.response.exit(code, body)\n            end\n        end\n    end\nend\n\n\nreturn _M\n",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- response_headers
X-limit-status: 2
--- no_error_log
[error]



=== TEST 3: hit routes again
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- response_headers
X-limit-status: 2
--- no_error_log
[error]



=== TEST 4: hit routes - limit count 2
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- response_headers
X-limit-status: 1
--- no_error_log
[error]
