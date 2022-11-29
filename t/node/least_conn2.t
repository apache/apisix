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

repeat_each(2);
log_level('info');
no_root_location();
worker_connections(1024);
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: upstream across multiple routes should not share the same version
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "type": "least_conn",
                    "nodes": {
                        "127.0.0.1:1980": 3,
                        "0.0.0.0:1980": 2
                    }
                 }]]
            )
            assert(code < 300, body)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "host": "1.com",
                    "uri": "/mysleep",
                    "upstream_id": "1"
                 }]]
            )
            assert(code < 300, body)
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "host": "2.com",
                    "uri": "/mysleep",
                    "upstream_id": "1"
                 }]]
            )
            assert(code < 300, body)
        }
    }



=== TEST 2: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/mysleep?seconds=0.1"

            local t = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri, {headers = {Host = i..".com"}})
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
        }
    }
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1980 while connecting to upstream
proxy request to 0.0.0.0:1980 while connecting to upstream
