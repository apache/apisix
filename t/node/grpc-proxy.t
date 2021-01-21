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

# As the test framework doesn't support sending grpc request, this
# test file is only for grpc irrelative configuration check.
# To avoid confusion, we configure a closed port so if th configuration works,
# the result will be `connect refused`.
repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    if (!$block->request) {
        $block->set_value("request", "POST /hello");
    }
});

run_tests();

__DATA__

=== TEST 1: with upstream_id
--- apisix_yaml
upstreams:
    - id: 1
      type: roundrobin
      nodes:
        "127.0.0.1:9088": 1
routes:
    - id: 1
      methods:
          - POST
      service_protocol: grpc
      uri: "/hello"
      upstream_id: 1
#END
--- error_code: 502
--- error_log
proxy request to 127.0.0.1:9088



=== TEST 2: with consummer
--- apisix_yaml
consumers:
  - username: jack
    id: jack
    plugins:
        key-auth:
            key: user-key
#END
routes:
    - id: 1
      methods:
          - POST
      service_protocol: grpc
      uri: "/hello"
      plugins:
          key-auth:
          consumer-restriction:
              whitelist:
                  - jack
      upstream:
          type: roundrobin
          nodes:
              "127.0.0.1:9088": 1
#END
--- more_headers
apikey: user-key
--- error_code: 502
