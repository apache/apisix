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
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests();

__DATA__

=== TEST 1: validate credentials
--- apisix_yaml
consumers:
  -
    username: john#1/credentials/john-a
    plugins:
      key-auth:
        key: auth-a      
routes:
  - uri: /hello
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
--- request
GET /hello
--- response_body
hello world
--- error_log
property "username" validation failed



=== TEST 2: validate the plugin under consumer
--- apisix_yaml
routes:
  - uri: /apisix/plugin/jwt/sign
    plugins:
        public-api: {}
consumers:
  - username: john_1/credentials/john-a
    plugins:
        jwt-auth:
            secret: my-secret-key
#END
--- request
GET /apisix/plugin/jwt/sign?key=user-key
--- error_log
plugin jwt-auth err: property "key" is required
--- error_code: 404



=== TEST 3: provide default value for the plugin
--- apisix_yaml
routes:
  - uri: /apisix/plugin/jwt/sign
    plugins:
        public-api: {}
consumers:
  - username: john_1/credentials/john-a
    plugins:
        jwt-auth:
            key: user-key
            secret: my-secret-key
#END
--- request
GET /apisix/plugin/jwt/sign?key=user-key
--- error_code: 200



=== TEST 4: test with username in id field - invalid key
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
      key-auth:
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
consumers:
  - id: rose/credentials/542f7414-87f6-4793-a68e-99983dde9913
    name: rose
    plugins:
      key-auth:
        key: csdt8UPw76/SG+WlHBoFeg==

  - id: rose
    username: rose
    plugins:
      limit-count:
        time_window: 3
        count: 100000000
        key_type: var
        allow_degradation: false
        key: remote_addr
        rejected_code: 429
        show_limit_quota_header: true
        policy: local
#END
--- more_headers
apikey: user-key
--- error_code: 401
--- request
POST /hello



=== TEST 5: test with username in id field - valid key
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
      key-auth:
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
consumers:
  - id: rose/credentials/542f7414-87f6-4793-a68e-99983dde9913
    name: rose
    plugins:
      key-auth:
        key: csdt8UPw76/SG+WlHBoFeg==

  - id: rose
    username: rose
    plugins:
      limit-count:
        time_window: 3
        count: 100000000
        key_type: var
        allow_degradation: false
        key: remote_addr
        rejected_code: 429
        show_limit_quota_header: true
        policy: local
#END
--- more_headers
apikey: csdt8UPw76/SG+WlHBoFeg==
--- error_code: 200
--- request
POST /hello
