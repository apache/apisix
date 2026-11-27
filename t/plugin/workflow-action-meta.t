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
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: two routes with a limit-count action that has its own _meta
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, id in ipairs({"1", "2"}) do
                local code, body = t('/apisix/admin/routes/' .. id, ngx.HTTP_PUT, {
                    uri = "/hello",
                    host = "r" .. id .. ".test",
                    plugins = {
                        workflow = {
                            rules = {{
                                actions = {{"limit-count", {
                                    _meta = {disable = false},
                                    count = 1,
                                    time_window = 60,
                                    rejected_code = 503,
                                    key = "remote_addr",
                                }}},
                            }},
                        },
                    },
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}},
                })
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: each route counts on a key of its own resource
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for _, host in ipairs({"r1.test", "r1.test", "r2.test"}) do
                local res = http.new():request_uri(uri, {headers = {Host = host}})
                ngx.say(host, " ", res.status)
            end
        }
    }
--- response_body
r1.test 200
r1.test 503
r2.test 200
--- error_log eval
[qr/limit key: \/apisix\/routes\/1[:#]/, qr/limit key: \/apisix\/routes\/2[:#]/]
