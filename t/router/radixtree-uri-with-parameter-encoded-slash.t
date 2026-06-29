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
worker_connections(256);
no_root_location();
no_shuffle();

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    preserve_encoded_slash: true
    router:
        http: 'radixtree_uri_with_parameter'
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: set route with path parameters
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/v1/:id/products/:type/list"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: encoded slash (%2F) in a path parameter is matched (not a separator)
--- request
GET /v1/te%2Fst/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 3: lowercase encoded slash (%2f) is matched
--- request
GET /v1/te%2fst/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 4: a serial number with multiple encoded slashes is matched
--- request
GET /v1/2024%2F01%2F0001/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 5: request without encoded slash still matches as before
--- request
GET /v1/test/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 6: other percent-encodings are still decoded (%20), still matches
--- request
GET /v1/te%20st/products/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 7: dot segments are normalized, route still matches
--- request
GET /v1/te%2Fst/products/foo/../electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/



=== TEST 8: encoded dot segment (%2e) is normalized, route still matches
--- request
GET /v1/te%2Fst/products/%2e/electronics/list
--- error_code: 404
--- response_body eval
qr/404 Not Found/
