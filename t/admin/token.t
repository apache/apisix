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
use Cwd qw(cwd);

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
_EOC_

    $block->set_value("yaml_config", $user_yaml_config);
});

run_tests;

__DATA__

=== TEST 1: set route without token
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").req_self_with_http
            local res, err = t('/apisix/admin/routes/1',
                "PUT",
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]]
                )

            ngx.status = res.status
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- error_code: 401
--- no_error_log
[error]



=== TEST 2: set route with wrong token
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").req_self_with_http
            local res, err = t(
                '/apisix/admin/routes/1',
                "PUT",
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]],
                {apikey = "wrong_key"}
                )

            ngx.status = res.status
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- error_code: 401
--- no_error_log
[error]



=== TEST 3: set route with correct token
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").req_self_with_http
            local res, err = t(
                '/apisix/admin/routes/1',
                "PUT",
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]],
                {x_api_key = "edd1c9f034335f136f87ad84b625c8f1"}
                )

            if res.status > 299 then
                ngx.status = res.status
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 4: get plugins name
--- request
GET /apisix/admin/plugins/list
--- error_code: 401
--- no_error_log
[error]



=== TEST 5: reload plugins
--- request
PUT /apisix/admin/plugins/reload
--- error_code: 401
--- no_error_log
[error]



=== TEST 6: reload plugins with api key(arguments)
--- request
PUT /apisix/admin/plugins/reload?api_key=edd1c9f034335f136f87ad84b625c8f1
--- error_code: 200
--- no_error_log
[error]



=== TEST 7: reload plugins with api key(cookie)
--- request
PUT /apisix/admin/plugins/reload
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
--- error_code: 200
--- no_error_log
[error]



=== TEST 8: reload plugins with api key(viewer role)
--- request
PUT /apisix/admin/plugins/reload?api_key=4054f7cf07e344346cd3f287985e76a2
--- error_code: 401
--- no_error_log
[error]



=== TEST 9: fetch with api key(viewer role)
--- request
GET /apisix/admin/routes??api_key=4054f7cf07e344346cd3f287985e76a2
--- error_code: 401
--- no_error_log
[error]
