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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

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

=== TEST: client-control rejects a gRPC request without Content-Length after internal redirect
--- http2
--- apisix_yaml
routes:
  - id: grpc-body-limit
    uri: /helloworld.Greeter/SayHello
    plugins:
      client-control:
        max_body_size: 1
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:10051": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello 2>&1
--- response_body_like: 413
--- error_log
client intended to send too large chunked body



=== TEST: client-control zero lets a gRPC body exceed the 30 MiB Nginx limit
--- http2
--- apisix_yaml
routes:
  - id: grpc-no-body-limit
    uri: /helloworld.Greeter/SayHello
    plugins:
      client-control:
        max_body_size: 0
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:10051": 1
      type: roundrobin
#END
--- exec
perl -e 'print "{\"name\":\"", "x" x (31 * 1024 * 1024), "\"}"' | grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d @ 127.0.0.1:1984 helloworld.Greeter.SayHello 2>&1
--- response_body_like: ResourceExhausted
--- timeout: 60



=== TEST: client-control raises the gRPC body limit above the 30 MiB Nginx limit
--- http2
--- apisix_yaml
routes:
  - id: grpc-larger-body-limit
    uri: /helloworld.Greeter/SayHello
    plugins:
      client-control:
        max_body_size: 52428800
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:10051": 1
      type: roundrobin
#END
--- exec
perl -e 'print "{\"name\":\"", "x" x (31 * 1024 * 1024), "\"}"' | grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d @ 127.0.0.1:1984 helloworld.Greeter.SayHello 2>&1
--- response_body_like: ResourceExhausted
--- timeout: 60
