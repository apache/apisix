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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
deployment:
    admin:
        admin_key:
            - name: admin
              role: admin
              key: edd1c9f034335f136f87ad84b625c8f1
            - name: viewer
              role: viewer
              key: ''
            - name: reader
              role: viewer
              key: reader-key-for-the-role-check
            - name: ops
              role: Admin
              key: ops-key-for-the-role-check
            - name: norole
              key: norole-key-for-the-role-check
apisix:
  node_listen: 1984
_EOC_

    $block->set_value("yaml_config", $user_yaml_config);
});

run_tests;

__DATA__

=== TEST 1: an empty api_key argument does not match an entry with an empty key
--- request
GET /apisix/admin/routes?api_key=
--- error_code: 401
--- response_body_like eval
qr/"description":"missing apikey"/



=== TEST 2: an empty X-API-KEY header does not match an entry with an empty key
--- request
GET /apisix/admin/routes
--- more_headers
X-API-KEY:
--- error_code: 401
--- response_body_like eval
qr/"description":"missing apikey"/



=== TEST 3: an empty x_api_key cookie does not match an entry with an empty key
--- request
GET /apisix/admin/routes
--- more_headers
Cookie: x_api_key=
--- error_code: 401
--- response_body_like eval
qr/"description":"missing apikey"/



=== TEST 4: a key whose role is Admin is refused
--- request
DELETE /apisix/admin/routes/1
--- more_headers
X-API-KEY: ops-key-for-the-role-check
--- error_code: 401
--- response_body_like eval
qr/"description":"invalid role"/



=== TEST 5: a key without a role is refused
--- request
GET /apisix/admin/routes
--- more_headers
X-API-KEY: norole-key-for-the-role-check
--- error_code: 401
--- response_body_like eval
qr/"description":"invalid role"/



=== TEST 6: the admin key still works
--- request
GET /apisix/admin/routes
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
--- error_code: 200



=== TEST 7: the viewer key can read routes
--- request
GET /apisix/admin/routes
--- more_headers
X-API-KEY: reader-key-for-the-role-check
--- error_code: 200



=== TEST 8: the viewer key cannot delete a route
--- request
DELETE /apisix/admin/routes/1
--- more_headers
X-API-KEY: reader-key-for-the-role-check
--- error_code: 401
--- response_body_like eval
qr/"description":"invalid method for role viewer"/
