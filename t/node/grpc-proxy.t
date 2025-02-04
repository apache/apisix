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
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
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
      scheme: grpc
      nodes:
        "127.0.0.1:9088": 1
routes:
    - id: 1
      methods:
          - POST
      uri: "/hello"
      upstream_id: 1
#END
--- error_code: 502
--- error_log
proxy request to 127.0.0.1:9088



=== TEST 2: with consumer
--- apisix_yaml
consumers:
  - username: jack
    plugins:
        key-auth:
            key: user-key
#END
routes:
    - id: 1
      methods:
          - POST
      uri: "/hello"
      plugins:
          key-auth:
          consumer-restriction:
              whitelist:
                  - jack
      upstream:
          scheme: grpc
          type: roundrobin
          nodes:
              "127.0.0.1:9088": 1
#END
--- more_headers
apikey: user-key
--- error_code: 502
--- error_log
Connection refused



=== TEST 3: with upstream_id (old way)
--- apisix_yaml
upstreams:
    - id: 1
      type: roundrobin
      scheme: grpc
      nodes:
        "127.0.0.1:9088": 1
routes:
    - id: 1
      methods:
          - POST
      uri: "/hello"
      upstream_id: 1
#END
--- error_code: 502
--- error_log
proxy request to 127.0.0.1:9088



=== TEST 4: with consumer (old way)
--- apisix_yaml
consumers:
  - username: jack
    plugins:
        key-auth:
            key: user-key
#END
routes:
    - id: 1
      methods:
          - POST
      uri: "/hello"
      plugins:
          key-auth:
          consumer-restriction:
              whitelist:
                  - jack
      upstream:
          type: roundrobin
          scheme: grpc
          nodes:
              "127.0.0.1:9088": 1
#END
--- more_headers
apikey: user-key
--- error_code: 502
--- error_log
Connection refused



=== TEST 5: use 443 as the grpcs' default port
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        scheme: grpcs
        nodes:
            "127.0.0.1": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 502
--- error_log
connect() failed (111: Connection refused) while connecting to upstream



=== TEST 6: use 80 as the grpc's default port
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        scheme: grpc
        nodes:
            "127.0.0.1": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 502
--- error_log
connect() failed (111: Connection refused) while connecting to upstream



=== TEST 7: set authority header
--- log_level: debug
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHello
    methods: [
        POST
    ]
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:10051": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
--- response_body
{
  "message": "Hello apisix"
}
--- grep_error_log eval
qr/grpc header: "(:authority|host): [^"]+"/
--- grep_error_log_out eval
qr/grpc header: "(:authority|host): 127.0.0.1:1984"/



=== TEST 8: set authority header to node header
--- log_level: debug
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHello
    methods: [
        POST
    ]
    upstream:
      scheme: grpc
      pass_host: node
      nodes:
        "127.0.0.1:10051": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
--- response_body
{
  "message": "Hello apisix"
}
--- grep_error_log eval
qr/grpc header: "(:authority|host): [^"]+"/
--- grep_error_log_out eval
qr/grpc header: "(:authority|host): 127.0.0.1:10051"/



=== TEST 9: set authority header to specific value
--- log_level: debug
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHello
    methods: [
        POST
    ]
    upstream:
      scheme: grpc
      pass_host: rewrite
      upstream_host: hello.world
      nodes:
        "127.0.0.1:10051": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
--- response_body
{
  "message": "Hello apisix"
}
--- grep_error_log eval
qr/grpc header: "(:authority|host): [^"]+"/
--- grep_error_log_out eval
qr/grpc header: "(:authority|host): hello.world"/
