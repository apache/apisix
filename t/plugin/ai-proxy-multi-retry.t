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

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
  - prometheus
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name fast_internal_error;
            default_type 'application/json';
            listen 6731;
            location / {
              content_by_lua_block {
                ngx.status = 500
                ngx.say([[{ "error": {"message":"fast internal error"}}]])
                return
              }
            }
        }
        server {
            server_name slow_internal_error;
            default_type 'application/json';
            listen 6732;
            location / {
              content_by_lua_block {
                ngx.sleep(0.5)
                ngx.status = 500
                ngx.say([[{ "error": {"message":"slow internal error"}}]])
                return
              }
            }
        }
        server {
            server_name success_instance;
            default_type 'application/json';
            listen 6733;
            location / {
              content_by_lua_block {
                ngx.status = 200
                ngx.print("success")
                return
              }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: max_retries caps fallback so all instances are not exhausted
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": ["http_5xx"],
                            "max_retries": 1,
                            "balancer": {
                                "algorithm": "roundrobin"
                            },
                            "instances": [
                                {"name":"err-1","provider":"openai-compatible","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6731"}},
                                {"name":"err-2","provider":"openai-compatible","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6731"}},
                                {"name":"err-3","provider":"openai-compatible","weight":1,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6731"}}
                            ],
                            "ssl_verify": false
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



=== TEST 2: request stops after max_retries and returns the upstream error (500, not 502)
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 500
--- error_log
reached max_retries 1



=== TEST 3: fast failure within retry_on_failure_within_ms still triggers fallback
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": ["http_5xx"],
                            "retry_on_failure_within_ms": 5000,
                            "instances": [
                                {"name":"fast-err","provider":"openai-compatible","weight":1,"priority":10,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6731"}},
                                {"name":"success","provider":"openai-compatible","weight":1,"priority":0,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6733"}}
                            ],
                            "ssl_verify": false
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



=== TEST 4: fast failure falls back to the healthy instance and logs the upstream error body
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- response_body chomp
success
--- error_code: 200
--- error_log
fast internal error



=== TEST 5: slow failure beyond retry_on_failure_within_ms is returned directly
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": ["http_5xx"],
                            "retry_on_failure_within_ms": 200,
                            "instances": [
                                {"name":"slow-err","provider":"openai-compatible","weight":1,"priority":10,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6732"}},
                                {"name":"success","provider":"openai-compatible","weight":1,"priority":0,"auth":{"header":{"Authorization":"Bearer token"}},"options":{"model":"gpt-4"},"override":{"endpoint":"http://127.0.0.1:6733"}}
                            ],
                            "ssl_verify": false
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



=== TEST 6: slow failure does not fall back and returns the upstream error body to the client
--- request
POST /anything
{ "messages": [ { "role": "user", "content": "What is 1+1?"} ] }
--- error_code: 500
--- response_body_like: slow internal error
--- error_log
exceeding retry_on_failure_within_ms 200
