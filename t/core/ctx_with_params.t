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
no_root_location();
no_shuffle();

our $yaml_config = <<_EOC_;
apisix:
    router:
        http: 'radixtree_uri_with_parameter'
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests;

__DATA__

=== TEST 1: add route and get `uri_param_`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"uri_param_id: \", ngx.ctx.api_ctx.var.uri_param_id) end"]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "uri": "/:id"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: `uri_param_id` exist (hello)
--- request
GET /hello
--- response_body
hello world
--- error_log
uri_param_id: hello



=== TEST 3: `uri_param_id` exist (hello1)
--- request
GET /hello1
--- response_body
hello1 world
--- error_log
uri_param_id: hello1



=== TEST 4: `uri_param_id` nonexisting route
--- request
GET /not_a_route
--- error_code: 404
--- error_log
uri_param_id: not_a_route



=== TEST 5: add route and get unknown `uri_param_id`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "access",
                            "functions" : ["return function() ngx.log(ngx.INFO, \"uri_param_id: \", ngx.ctx.api_ctx.var.uri_param_id) end"]
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: `uri_param_id` not in uri
--- request
GET /hello
--- response_body
hello world
--- error_log
uri_param_id:
