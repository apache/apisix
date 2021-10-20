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

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    config_center: yaml
    node_listen:
        - port: 9080
          enable_http2: false
        - port: 9081
          enable_http2: true
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__


=== TEST 1: Unary API gRPC
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
        "127.0.0.1:50051": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local ngx_pipe = require("ngx.pipe")
            local proc, err = ngx_pipe.spawn("grpcurl -plaintext -d '{\"name\":\"apisix\"}' 127.0.0.1:50051 helloworld.Greeter.SayHello")
            if not proc then
                ngx.say(err)
                return
            end
            local data, err = proc:stdout_read_all()
            if not data then
                ngx.say(err)
                return
            end
            ngx.say(data:sub(1, -2))
            return
        }
    }
--- response_body
{
  "message": "Hello apisix"
}


=== TEST 2: Server side streaming gRPC
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHelloMultiReply
    methods: [
        POST
    ]
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:50051": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local ngx_pipe = require("ngx.pipe")
            local proc, err = ngx_pipe.spawn("grpcurl -plaintext -d '{\"name\":\"apisix\"}' 127.0.0.1:50051 helloworld.Greeter.SayHelloMultiReply")
            if not proc then
                ngx.say(err)
                return
            end
            local data, err = proc:stdout_read_all()
            if not data then
                ngx.say(err)
                return
            end
            ngx.say(data:sub(1, -2))
            return
        }
    }
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

=== TEST 3: Client side streaming gRPC
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHelloMultiReq
    methods: [
        POST
    ]
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:50051": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local ngx_pipe = require("ngx.pipe")
            local proc, err = ngx_pipe.spawn("grpcurl -plaintext -d '{\"name\":\"apisix\"} {\"name\":\"apisix\"} {\"name\":\"apisix\"}' 127.0.0.1:50051 helloworld.Greeter.SayHelloMultiReq")
            if not proc then
                ngx.say(err)
                return
            end
            local data, err = proc:stdout_read_all()
            if not data then
                ngx.say(err)
                return
            end
            ngx.say(data:sub(1, -2))
            return
        }
    }
--- response_body
{
  "message": "Hello apisix!Hello apisix!Hello apisix!"
}

=== TEST 4: Bidirectional streaming gRPC
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHelloMulti
    methods: [
        POST
    ]
    upstream:
      scheme: grpc
      nodes:
        "127.0.0.1:50051": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local ngx_pipe = require("ngx.pipe")
            local proc, err = ngx_pipe.spawn("grpcurl -plaintext -d '{\"name\":\"apisix\"} {\"name\":\"apisix\"}' 127.0.0.1:50051 helloworld.Greeter.SayHelloMulti")
            if not proc then
                ngx.say(err)
                return
            end
            local data, err = proc:stdout_read_all()
            if not data then
                ngx.say(err)
                return
            end
            ngx.say(data:sub(1, -2))
            return
        }
    }
--- response_body
{
  "message": "Hello apisix"
}
{
  "message": "Hello apisix"
}
{
  "message": "stream ended"
}
