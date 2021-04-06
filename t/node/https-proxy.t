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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: add route to HTTPS upstream (old way)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "plugins": {
                        "proxy-rewrite": {
                            "scheme": "https"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1983": 1
                        }
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
--- request
GET /t
--- response_body
passed



=== TEST 2: hit the upstream (old way)
--- request
GET /hello
--- more_headers
host: www.sni.com
--- error_log
Receive SNI: www.sni.com



=== TEST 3: add route to HTTPS upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "scheme": "https",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1983": 1
                        }
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
--- request
GET /t
--- response_body
passed



=== TEST 4: hit the upstream
--- request
GET /hello
--- more_headers
host: www.sni.com
--- error_log
Receive SNI: www.sni.com



=== TEST 5: add route to HTTPS upstream (mix)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "plugins": {
                        "proxy-rewrite": {
                            "scheme": "https"
                        }
                    },
                    "upstream": {
                        "scheme": "https",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1983": 1
                        }
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
--- request
GET /t
--- response_body
passed



=== TEST 6: hit the upstream
--- request
GET /hello
--- more_headers
host: www.sni.com
--- error_log
Receive SNI: www.sni.com



=== TEST 7: use 443 as the default port
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        scheme: https
        nodes:
            "127.0.0.1": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 502
--- error_log
upstream: "https://127.0.0.1:443/hello"



=== TEST 8: use 80 as the http's default port
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 502
--- error_log
upstream: "http://127.0.0.1:80/hello"



=== TEST 9: rewrite SNI
--- log_level: debug
--- apisix_yaml
routes:
  -
    uri: /uri
    upstream:
        scheme: https
        nodes:
            "127.0.0.1:1983": 1
        type: roundrobin
        pass_host: "rewrite",
        upstream_host: "www.test.com",
#END
--- request
GET /uri
--- more_headers
host: www.sni.com
--- error_log
Receive SNI: www.test.com
--- response_body
uri: /uri
host: www.test.com
x-real-ip: 127.0.0.1



=== TEST 10: node's SNI
--- log_level: debug
--- apisix_yaml
routes:
  -
    uri: /uri
    upstream:
        scheme: https
        nodes:
            "localhost:1983": 1
        type: roundrobin
        pass_host: "node",
#END
--- request
GET /uri
--- more_headers
host: www.sni.com
--- error_log
Receive SNI: localhost
--- response_body
uri: /uri
host: localhost
x-real-ip: 127.0.0.1
