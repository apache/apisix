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

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_host_uri'
    admin_key: null
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("yaml_config", $yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log &&
        (defined $block->error_code && $block->error_code != 502))
    {
        $block->set_value("no_error_log", "[error]");
    }

    $block;
});

run_tests();

__DATA__

=== TEST 1: change hosts in services
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "hosts": ["foo.com"]
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "service_id": "1",
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {headers = {Host = "foo.com"}})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)

            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "hosts": ["bar.com"]
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.1)

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {headers = {Host = "foo.com"}})
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
        }
    }
--- response_body
hello world
404
