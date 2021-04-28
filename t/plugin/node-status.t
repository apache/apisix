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

    my $extra_yaml_config = <<_EOC_;
plugins:
    - node-status
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    $block;
});

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.5)
        local t = require("lib.test_admin").test
        local code, body, body_org = t('/apisix/status', ngx.HTTP_GET)

        if code >= 300 then
            ngx.status = code
        end
        ngx.say(body_org)
    }
}
--- request
GET /t
--- response_body eval
qr/"accepted":/
--- no_error_log
[error]



=== TEST 2: test for unsupported method
--- request
PATCH /apisix/status
--- error_code: 404



=== TEST 3: test for use default uuid as apisix_uid
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.5)
        local t = require("lib.test_admin").test
        local code, body, body_org = t('/apisix/status', ngx.HTTP_GET)

        if code >= 300 then
            ngx.status = code
        end
        local json_decode = require("cjson").decode
        local body_json = json_decode(body_org)
        ngx.say(body_json.id)
    }
}
--- request
GET /t
--- response_body_like eval
qr/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
--- no_error_log
[error]



=== TEST 4: test for allow user to specify a meaningful id as apisix_uid
--- yaml_config
apisix:
    id: "user-set-apisix-instance-id-A"
#END
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(0.5)
        local t = require("lib.test_admin").test
        local code, body, body_org = t('/apisix/status', ngx.HTTP_GET)

        if code >= 300 then
            ngx.status = code
        end
        ngx.say(body_org)
    }
}
--- request
GET /t
--- response_body eval
qr/"id":"user-set-apisix-instance-id-A"/
--- no_error_log
[error]
