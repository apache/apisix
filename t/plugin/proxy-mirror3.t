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

    # a h2c server that records the mirrored gRPC request
    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 19797;
        http2 on;
        location / {
            content_by_lua_block {
                ngx.req.read_body()
                local body = ngx.req.get_body_data()
                ngx.log(ngx.WARN, "grpc mirror server got request: path=",
                        ngx.var.request_uri,
                        " content_type=", ngx.var.http_content_type or "",
                        " body_len=", body and #body or 0)
                ngx.header["Content-Type"] = "application/grpc"
                ngx.exit(200)
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "POST /hello");
    }
});

run_tests;

__DATA__

=== TEST 1: grpc mirror
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
    plugins:
        proxy-mirror:
            host: grpc://127.0.0.1:19797
            sample_ratio: 1
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:10051": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
sleep 0.5
--- response_body
{
  "message": "Hello apisix"
}
--- error_log
grpc mirror server got request: path=/helloworld.Greeter/SayHello content_type=application/grpc body_len=13



=== TEST 2: grpc mirror keeps the URI rewritten by access phase plugins (grpc-web)
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /grpc/web/*
    plugins:
        grpc-web: {}
        proxy-mirror:
            host: grpc://127.0.0.1:19797
            sample_ratio: 1
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:10051": 1
      type: roundrobin
#END
--- exec
printf '\000\000\000\000\010\012\006apisix' | curl -s -o /dev/null -w "code=%{http_code}" -X POST \
    -H 'Content-Type: application/grpc-web+proto' --data-binary @- \
    http://127.0.0.1:1984/grpc/web/helloworld.Greeter/SayHello
sleep 0.5
--- response_body chomp
code=200
--- error_log
grpc mirror server got request: path=/helloworld.Greeter/SayHello content_type=application/grpc body_len=13
