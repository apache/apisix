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
no_shuffle();
no_root_location();
log_level('info');
worker_connections(1024);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 1986;
        server_tokens off;

        location / {
            content_by_lua_block {
                local core = require("apisix.core")
                core.log.info("upstream_http_version: ", ngx.req.http_version())

                local headers_tab = ngx.req.get_headers()
                local headers_key = {}
                for k in pairs(headers_tab) do
                    core.table.insert(headers_key, k)
                end
                core.table.sort(headers_key)

                for _, v in pairs(headers_key) do
                    core.log.info(v, ": ", headers_tab[v])
                end

                core.log.info("uri: ", ngx.var.request_uri)
                ngx.say("hello world")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
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



=== TEST 2: sanity check (normal case)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "proxy-mirror": {
                               "host": "http://127.0.0.1:1986"
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
--- request
GET /t
--- error_code: 200
--- response_body
passed



=== TEST 3: hit route
--- exec
curl -k -v -H "Host: test.com" -H "content-length: 0" --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/hello 2>&1 | cat
--- response_body_like
hello world
--- response_body eval
qr/HTTP\/3 200/
--- error_log
uri: /hello
