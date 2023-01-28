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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: set binary rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")

            local content = t.read_file("t/grpc_server_example/helloworld.pb")
            local data = {content = ngx.encode_base64(content)}
            local code, body = t.test('/apisix/admin/protos/1',
                 ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/grpctest",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "EchoStruct"
                        }
                    },
                    "upstream": {
                        "scheme": "grpc",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:50051": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: hit route
--- config
location /t {
    content_by_lua_block {
        local core = require "apisix.core"
        local http = require "resty.http"
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/grpctest"
        local body = [[{"data":{"fields":{"foo":{"string_value":"xxx"},"bar":{"number_value":666}}}}]]
        local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}, keepalive = false}
        local httpc = http.new()
        local res, err = httpc:request_uri(uri, opt)
        if not res then
            ngx.log(ngx.ERR, err)
            return ngx.exit(500)
        end
        if res.status > 300 then
            return ngx.exit(res.status)
        else
            local rsp = core.json.decode(res.body)
            assert(core.table.deep_eq(rsp, core.json.decode(body)))
        end
    }
}
