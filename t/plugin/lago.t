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



=== TEST 2: test
--- timeout: 300
--- max_size: 2048000
--- exec
cd t && pnpm test plugin/lago.spec.mts 2>&1
--- no_error_log
failed to execute the script with status
--- response_body eval
qr/PASS plugin\/lago.spec.mts/
