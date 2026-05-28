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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $yaml_config = <<_EOC_;
apisix:
  request_body_json_lib: simdjson
_EOC_
    $block->set_value("yaml_config", $yaml_config);

    my $extra_yaml_config = <<_EOC_;
nginx_config:
  worker_processes: 1
_EOC_
    $block->set_value("extra_yaml_config", $extra_yaml_config);
});

run_tests();

__DATA__

=== TEST 1: ai-proxy route with post_arg.model keeps matching after simdjson decode errors
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/anything",
                    "vars": [
                        [
                            ["post_arg.model", "==", "gpt-4"]
                        ]
                    ],
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai-compatible",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "override": {
                                "endpoint": "http://127.0.0.1:1980"
                            },
                            "ssl_verify": false
                        }
                    }
                }]=]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.2)

            local http = require("resty.http")
            local httpc = http.new()

            local function post(body)
                local res, err = httpc:request_uri("http://127.0.0.1:1984/anything", {
                    method = "POST",
                    body = body,
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Authorization"] = "Bearer token",
                        ["X-AI-Fixture"] = "openai/chat-basic.json",
                    },
                })

                if not res then
                    ngx.say("request error: ", err)
                    return nil
                end

                return res
            end

            local good = [[{"model":"gpt-4","messages":[{"role":"user","content":"test prompt"}]}]]

            local function check_sequence(name, bad)
                local res = post(bad)
                ngx.say(name, " poison status: ", res and res.status)

                res = post(good)
                ngx.say(name, " first valid status: ", res and res.status)
                ngx.say(name, " first valid ai-proxy response: ",
                        res and res.body and res.body:find("1 + 1 = 2.", 1, true) ~= nil)

                res = post(good)
                ngx.say(name, " second valid status: ", res and res.status)
                ngx.say(name, " second valid ai-proxy response: ",
                        res and res.body and res.body:find("1 + 1 = 2.", 1, true) ~= nil)
            end

            check_sequence("string", [[{"model":["\uD800"]}]])
            check_sequence("structure", [[{"model":[1,]}]])
        }
    }
--- response_body
string poison status: 404
string first valid status: 200
string first valid ai-proxy response: true
string second valid status: 200
string second valid ai-proxy response: true
structure poison status: 404
structure first valid status: 200
structure first valid ai-proxy response: true
structure second valid status: 200
structure second valid ai-proxy response: true
--- error_log
failed to decode request body with simdjson: simdjson: error: STRING_ERROR: Problem while parsing a string, falling back to cjson
failed to decode request body with simdjson: simdjson: error: TAPE_ERROR: The JSON document has an improper structure: missing or superfluous commas, braces, missing keys, etc., falling back to cjson
--- no_error_log
failed to fetch post args value by key: model error: could not parse JSON request body: simdjson: error: trailing content found
