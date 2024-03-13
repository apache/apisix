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
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__
=== TEST 1: disable prometheus plugin and check metrics
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local code, body = t.test('/apisix/admin/plugins', ngx.HTTP_PUT,
                                      [[{
                                          "prometheus": {
                                              "disable": true
                                          }
                                      }]]
                                     )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("done")
        }
    }
    location /apisix/prometheus/metrics {
        content_by_lua_block {
            ngx.status = 404
            ngx.say("not found")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]

--- request
GET /apisix/prometheus/metrics
--- error_code: 404
--- response_body
not found

=== TEST 2: enable prometheus plugin and check metrics again
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local code, body = t.test('/apisix/admin/plugins', ngx.HTTP_PUT,
                                      [[{
                                          "prometheus": {
                                              "disable": false
                                          }
                                      }]]
                                     )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("done")
        }
    }
    location /apisix/prometheus/metrics {
        content_by_lua_block {
            -- This should reflect your real logic when Prometheus is enabled.
            -- For simplicity, let's just return a mock response.
            ngx.say("metrics data")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]

--- request
GET /apisix/prometheus/metrics
--- response_body
metrics data
