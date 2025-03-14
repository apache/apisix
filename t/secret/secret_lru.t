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
run_tests;

__DATA__

=== TEST 1: add secret  && consumer && check
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- put secret vault config
            local code, body = t('/apisix/admin/secrets/vault/mysecret',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix": "kv-v1/apisix",
                    "token": "root"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            -- change consumer with secrets ref: vault
            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                          "key-auth": {
                            "key": "$secret://vault/mysecret/jack/auth-key"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end


            local secret = require("apisix.secret")
            local value = secret.fetch_by_uri("$secret://vault/mysecret/jack/auth-key")


            local code, body = t('/apisix/admin/secrets/vault/mysecret', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                          "key-auth": {
                            "key": "$secret://vault/mysecret/jack/auth-key"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local secret = require("apisix.secret")
            local value = secret.fetch_by_uri("$secret://vault/mysecret/jack/auth-key")
            ngx.say(value)
        }
    }
--- response_body
nil
--- error_log
failed to fetch secret value: no secret conf, secret_uri: $secret://vault/mysecret/jack/auth-key
