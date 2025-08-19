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

no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /apisix/admin/routes");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: Server header for admin API
--- response_headers_like
Server: APISIX/(.*)



=== TEST 2: Server header for admin API without token
--- yaml_config
deployment:
    admin:
        admin_key:
            - key: a
              name: a
              role: admin
apisix:
  node_listen: 1984
  enable_server_tokens: false
--- error_code: 401
--- response_headers
Server: APISIX



=== TEST 3: Version header for admin API (without apikey)
--- yaml_config
deployment:
    admin:
        admin_key:
            - key: a
              name: a
              role: admin
apisix:
  admin_api_version: default
--- error_code: 401
--- response_headers
! X-API-VERSION



=== TEST 4: Version header for admin API (v2)
--- yaml_config
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: ~
    admin_api_version: v2
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
--- response_headers
X-API-VERSION: v2



=== TEST 5: Version header for admin API (v3)
--- yaml_config
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: ~
    admin_api_version: v3
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
--- response_headers
X-API-VERSION: v3



=== TEST 6: CORS header for admin API
--- response_headers
Access-Control-Allow-Origin: *



=== TEST 7: CORS header disabled for admin API
--- yaml_config
deployment:
    admin:
        admin_key: ~
        enable_admin_cors: false
--- response_headers
Access-Control-Allow-Origin:



=== TEST 8: Compatibility for admin API (v2)
--- yaml_config
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: ~
    admin_api_version: default
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
--- response_headers
X-API-VERSION: v2
--- response_body_like: "/apisix/routes"



=== TEST 9: Head method support for admin API
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin',
                ngx.HTTP_HEAD)
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: Access with api key, and admin_key_required=true
--- yaml_config
deployment:
  admin:
    admin_key_required: true
    admin_key:
    - name: admin
      role: admin
      key: rDAkLJbqvoBzBOoxuYAUDbbWaSilvIca
--- more_headers
X-API-KEY: rDAkLJbqvoBzBOoxuYAUDbbWaSilvIca
--- request
GET /apisix/admin/routes
--- error_code: 200



=== TEST 11: Access with wrong api key, and admin_key_required=true
--- yaml_config
deployment:
  admin:
    admin_key_required: true
--- more_headers
X-API-KEY: wrong-key
--- request
GET /apisix/admin/routes
--- error_code: 401



=== TEST 12: Access without api key, and admin_key_required=true
--- yaml_config
deployment:
  admin:
    admin_key_required: true
--- request
GET /apisix/admin/routes
--- error_code: 401



=== TEST 13: Access with api key, but admin_key_required=false
--- yaml_config
deployment:
  admin:
    admin_key_required: false
    admin_key:
    - name: admin
      role: admin
      key: rDAkLJbqvoBzBOoxuYAUDbbWaSilvIca
--- more_headers
X-API-KEY: rDAkLJbqvoBzBOoxuYAUDbbWaSilvIca
--- request
GET /apisix/admin/routes
--- error_code: 200
--- error_log
Admin key is bypassed!



=== TEST 14: Access with wrong api key, but admin_key_required=false
--- yaml_config
deployment:
  admin:
    admin_key_required: false
--- more_headers
X-API-KEY: wrong-key
--- request
GET /apisix/admin/routes
--- error_code: 200
--- error_log
Admin key is bypassed!



=== TEST 15: Access without api key, but admin_key_required=false
--- yaml_config
deployment:
  admin:
    admin_key_required: false
--- request
GET /apisix/admin/routes
--- error_code: 200
--- error_log
Admin key is bypassed!
