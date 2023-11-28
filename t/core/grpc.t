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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: unary
--- config
    location /t {
        content_by_lua_block {
            local core = require "apisix.core"
            local gcli = core.grpc
            assert(gcli.load("t/grpc_server_example/proto/helloworld.proto"))
            local conn = assert(gcli.connect("127.0.0.1:10051"))
            local res, err = conn:call("helloworld.Greeter", "SayHello", {
                                        name = "apisix" })
            conn:close()
            if not res then
                ngx.status = 503
                ngx.say(err)
                return
            end
            ngx.say(res.message)
        }
    }
--- response_body
Hello apisix



=== TEST 2: server stream
--- config
    location /t {
        content_by_lua_block {
            local core = require "apisix.core"
            local gcli = core.grpc
            assert(gcli.load("t/grpc_server_example/proto/helloworld.proto"))
            local conn = assert(gcli.connect("127.0.0.1:10051"))
            local st, err = conn:new_server_stream("helloworld.Greeter",
                "SayHelloServerStream", { name = "apisix" })
            if not st then
                ngx.status = 503
                ngx.say(err)
                return
            end

            for i = 1, 5 do
                local res, err = st:recv()
                if not res then
                    ngx.status = 503
                    ngx.say(err)
                    return
                end
                ngx.say(res.message)
            end
        }
    }
--- response_body eval
"Hello apisix\n" x 5



=== TEST 3: client stream
--- config
    location /t {
        content_by_lua_block {
            local core = require "apisix.core"
            local gcli = core.grpc
            assert(gcli.load("t/grpc_server_example/proto/helloworld.proto"))
            local conn = assert(gcli.connect("127.0.0.1:10051"))
            local st, err = conn:new_client_stream("helloworld.Greeter",
                "SayHelloClientStream", { name = "apisix" })
            if not st then
                ngx.status = 503
                ngx.say(err)
                return
            end

            for i = 1, 3 do
                local ok, err = st:send({ name = "apisix" })
                if not ok then
                    ngx.status = 503
                    ngx.say(err)
                    return
                end
            end

            local res, err = st:recv_close()
            if not res then
                ngx.status = 503
                ngx.say(err)
                return
            end
            ngx.say(res.message)
        }
    }
--- response_body
Hello apisix!Hello apisix!Hello apisix!Hello apisix!



=== TEST 4: bidirectional stream
--- config
    location /t {
        content_by_lua_block {
            local core = require "apisix.core"
            local gcli = core.grpc
            assert(gcli.load("t/grpc_server_example/proto/helloworld.proto"))
            local conn = assert(gcli.connect("127.0.0.1:10051"))
            local st, err = conn:new_bidirectional_stream("helloworld.Greeter",
                "SayHelloBidirectionalStream", { name = "apisix" })
            if not st then
                ngx.status = 503
                ngx.say(err)
                return
            end

            for i = 1, 3 do
                local ok, err = st:send({ name = "apisix" })
                if not ok then
                    ngx.status = 503
                    ngx.say(err)
                    return
                end
            end

            assert(st:close_send())
            for i = 1, 5 do
                local res, err = st:recv()
                if not res then
                    ngx.status = 503
                    ngx.say(err)
                    return
                end
                ngx.say(res.message)
            end
        }
    }
--- response_body eval
"Hello apisix\n" x 4 . "stream ended\n"
