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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {endpoint_addrs = {"http://127.0.0.1:3000"}, token = "token", event_transaction_id = "tid", event_subscription_id = "sid", event_code = "code"},
                {endpoint_addrs = "http://127.0.0.1:3000", token = "token", event_transaction_id = "tid", event_subscription_id = "sid", event_code = "code"},
                {endpoint_addrs = {}, token = "token", event_transaction_id = "tid", event_subscription_id = "sid", event_code = "code"},
                {endpoint_addrs = {"http://127.0.0.1:3000"}, endpoint_uri = "/test", token = "token", event_transaction_id = "tid", event_subscription_id = "sid", event_code = "code"},
                {endpoint_addrs = {"http://127.0.0.1:3000"}, endpoint_uri = 1234, token = "token", event_transaction_id = "tid", event_subscription_id = "sid", event_code = "code"},
                {endpoint_addrs = {"http://127.0.0.1:3000"}, token = 1234, event_transaction_id = "tid", event_subscription_id = "sid", event_code = "code"},
                {endpoint_addrs = {"http://127.0.0.1:3000"}, token = "token", event_transaction_id = "tid", event_subscription_id = "sid", event_code = "code", event_properties = {key = "value"}},
                {endpoint_addrs = {"http://127.0.0.1:3000"}, token = "token", event_transaction_id = "tid", event_subscription_id = "sid", event_code = "code", event_properties = {1,2,3}},
            }
            local plugin = require("apisix.plugins.lago")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
property "endpoint_addrs" validation failed: wrong type: expected array, got string
property "endpoint_addrs" validation failed: expect array to have at least 1 items
done
property "endpoint_uri" validation failed: wrong type: expected string, got number
property "token" validation failed: wrong type: expected string, got number
done
property "event_properties" validation failed: wrong type: expected object, got table



=== TEST 2: set up a route whose lago plugin sends events to the mock endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "lago": {
                            "endpoint_addrs": ["http://127.0.0.1:1980"],
                            "token": "test-token",
                            "event_transaction_id": "txn-${request_id}",
                            "event_subscription_id": "sub-1",
                            "event_code": "test",
                            "event_properties": {
                                "tier": "normal",
                                "status": "${status}"
                            },
                            "batch_max_size": 1
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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



=== TEST 3: hitting the route batches one event and sends it to the mock
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
lago auth: Bearer test-token
"code":"test"
"external_subscription_id":"sub-1"
"transaction_id":"txn-
"tier":"normal"
"status":"200"
