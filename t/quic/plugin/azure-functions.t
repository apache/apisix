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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $inside_lua_block = $block->inside_lua_block // "";
    chomp($inside_lua_block);
    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 8765;

        location /httptrigger {
            content_by_lua_block {
                ngx.req.read_body()
                local msg = "faas invoked"
                ngx.header['Content-Length'] = #msg + 1
                ngx.header['X-Extra-Header'] = "MUST"
                ngx.header['Connection'] = "Keep-Alive"
                ngx.say(msg)
            }
        }

        location  /api {
           content_by_lua_block {
                ngx.say("invocation /api successful")
            }
        }

        location /api/httptrigger {
           content_by_lua_block {
                ngx.say("invocation /api/httptrigger successful")
            }
        }

        location /api/http/trigger {
           content_by_lua_block {
                ngx.say("invocation /api/http/trigger successful")
            }
        }

        location /azure-demo {
            content_by_lua_block {
                $inside_lua_block
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1:  create ssl for test.com
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com"
                    },
                    "key": "/apisix/ssls/1"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: create route with azure-function plugin enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "azure-functions": {
                                "function_uri": "http://localhost:8765/httptrigger"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/azure"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: test plugin endpoint
--- exec
curl -k -v -H "Host: test.com" -H "content-length: 0" --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/azure 2>&1 | cat
--- response_body_like
faas invoked
--- response_body eval
qr/content-length: 13/
--- response_body_like
x-extra-header: MUST
