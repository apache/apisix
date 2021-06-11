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

log_level('info');
no_root_location();
worker_connections(1024);
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: set stream / ssl
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {
                cert = ssl_cert, key = ssl_key,
                sni = "test.com",
            }
            local code, body = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                core.json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            local code, body = t.test('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 2: hit route
--- stream_tls_request
mmm
--- stream_sni: test.com
--- response_body
hello world



=== TEST 3: wrong sni
--- stream_tls_request
mmm
--- stream_sni: xx.com
--- error_log
failed to find any SSL certificate by SNI: xx.com



=== TEST 4: missing sni
--- stream_tls_request
mmm
--- error_log
failed to find SNI
