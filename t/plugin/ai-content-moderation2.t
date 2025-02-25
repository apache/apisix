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


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "ai-content-moderation": {
                            "provider": {
                                "aws_comprehend": {
                                    "access_key_id": "access",
                                    "secret_access_key": "ea+secret",
                                    "region": "us-east-1",
                                    "endpoint": "http://localhost:2668"
                                }
                            },
                            "llm_provider": "openai"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: request should fail
--- request
POST /echo
{"model":"gpt-4o-mini","messages":[{"role":"user","content":"toxic"}]}
--- error_code: 500
--- response_body chomp
Comprehend:detectToxicContent() failed to connect to 'http://localhost:2668': connection refused
--- error_log
failed to send request to http://localhost: Comprehend:detectToxicContent() failed to connect to 'http://localhost:2668': connection refused
