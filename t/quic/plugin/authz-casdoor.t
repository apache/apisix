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

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 10420;
        location /api/login/oauth/access_token {
            content_by_lua_block {
                local json_encode = require("toolkit.json").encode
                ngx.req.read_body()
                local arg = ngx.req.get_post_args()["code"]

                local core = require("apisix.core")
                local log = core.log

                if arg == "wrong" then
                    ngx.status = 200
                    ngx.say(json_encode({ access_token = "bbbbbbbbbb", expires_in = 0 }))
                    return
                end

                ngx.status = 200
                ngx.say(json_encode({ access_token = "aaaaaaaaaaaaaaaa", expires_in = 1000000 }))
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});
run_tests();

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



=== TEST 2: enable plugin test redirect
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local t = require("lib.test_admin").test

            local fake_uri = "http://127.0.0.1:10420"
            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback"
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/anything/*",
                    "plugins": {
                        "authz-casdoor": {
                            "callback_url":"]] .. callback_url .. [[",
                            "endpoint_addr":"]] .. fake_uri .. [[",
                            "client_id":"7ceb9b7fda4a9061ec1c",
                            "client_secret":"3416238e1edf915eac08b8fe345b2b95cdba7e04"
                        },
                        "proxy-rewrite": {
                            "uri": "/echo"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "test.com:1980": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.say("failed to set up routing rule")
            end
            ngx.say("done")

        }
    }
--- response_body
done



=== TEST 3: test redirect
--- exec
curl -k -v -H "Host: test.com" -H "Content-Length: 0" -G --data-urlencode "param1=foo" --data-urlencode "param2=bar" --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/anything/d? 2>&1 | cat
--- response_body eval
qr/HTTP\/3 302/
