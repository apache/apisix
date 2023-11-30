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
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: Test server side streaming method through gRPC proxy
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHelloServerStream
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
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHelloServerStream
--- response_body
{
  "message": "Hello apisix"
}
{
  "message": "Hello apisix"
}
{
  "message": "Hello apisix"
}
{
  "message": "Hello apisix"
}
{
  "message": "Hello apisix"
}



=== TEST 2: Test client side streaming method through gRPC proxy
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHelloClientStream
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
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"} {"name":"apisix"} {"name":"apisix"} {"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHelloClientStream
--- response_body
{
  "message": "Hello apisix!Hello apisix!Hello apisix!Hello apisix!"
}



=== TEST 3: Test bidirectional streaming method through gRPC proxy
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHelloBidirectionalStream
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
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"} {"name":"apisix"} {"name":"apisix"} {"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHelloBidirectionalStream
--- response_body
{
  "message": "Hello apisix"
}
{
  "message": "Hello apisix"
}
{
  "message": "Hello apisix"
}
{
  "message": "Hello apisix"
}
{
  "message": "stream ended"
}
