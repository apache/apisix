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

BEGIN {
    $ENV{AWS_REGION} = "us-east-1";
    $ENV{AWS_ACCESS_KEY_ID} = "access";
    $ENV{AWS_SECRET_ACCESS_KEY} = "secret";
    $ENV{AWS_SESSION_TOKEN} = "token";
    $ENV{AWS_REGION_LOCAL} = "us-east-1";
    $ENV{AWS_ACCESS_KEY_ID_LOCAL} = "access";
    $ENV{AWS_SECRET_ACCESS_KEY_LOCAL} = "secret";
    $ENV{AWS_SESSION_TOKEN_LOCAL} = "token";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

run_tests;

__DATA__

=== TEST 1: check key: error format
--- config
    location /t {
        content_by_lua_block {
            local aws = require("apisix.secret.aws")
            local conf = {
                endpoint_url = "http://127.0.0.1:4566",
                region = "us-east-1",
                access_key_id = "access",
                secret_access_key = "secret",
                session_token = "token",
            }
            local data, err = aws.get(conf, "apisix")
            if err then
                return ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
error key format, key: apisix



=== TEST 2: check key: no main key
--- config
    location /t {
        content_by_lua_block {
            local aws = require("apisix.secret.aws")
            local conf = {
                endpoint_url = "http://127.0.0.1:4566",
                region = "us-east-1",
                access_key_id = "access",
                secret_access_key = "secret",
                session_token = "token",
            }
            local data, err = aws.get(conf, "/apisix")
            if err then
                return ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
can't find main key, key: /apisix



=== TEST 3: check key: no sub key
--- config
    location /t {
        content_by_lua_block {
            local aws = require("apisix.secret.aws")
            local conf = {
                endpoint_url = "http://127.0.0.1:4566",
                region = "us-east-1",
                access_key_id = "access",
                secret_access_key = "secret",
                session_token = "token",
            }
            local data, err = aws.get(conf, "apisix/")
            if err then
                return ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
can't find sub key, key: apisix/



=== TEST 4: error aws endpoint_url
--- config
    location /t {
        content_by_lua_block {
            local aws = require("apisix.secret.aws")
            local conf = {
                endpoint_url = "http://127.0.0.1:8080",
                region = "us-east-1",
                access_key_id = "access",
                secret_access_key = "secret",
                session_token = "token",
            }
            local data, err = aws.get(conf, "/apisix-key/jack/key")
            if err then
                return ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
failed to retrtive data from aws secret manager: SecretsManager:getSecretValue() failed to connect to 'http://127.0.0.1:8080': connection refused
--- timeout: 6



=== TEST 5: error aws region
--- config
    location /t {
        content_by_lua_block {
            local aws = require("apisix.secret.aws")
            local conf = {
                endpoint_url = "http://127.0.0.1:4566",
                region = "error-region",
                access_key_id = "access",
                secret_access_key = "secret",
                session_token = "token",
            }
            local data, err = aws.get(conf, "/apisix-key/jack/key")
            if err then
                return ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
failed to retrtive data from aws secret manager: (invalid status)
--- timeout: 20



=== TEST 6: get value from aws
--- config
    location /t {
        content_by_lua_block {
            local aws = require("apisix.secret.aws")
            local conf = {
                endpoint_url = "http://127.0.0.1:4566",
                region = "us-east-1",
                access_key_id = "access",
                secret_access_key = "secret",
                session_token = "token",
            }
            local data, err = aws.get(conf, "/apisix-key/jack/key")
            if err then
                return ngx.say(err)
            end
            ngx.say("value")
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 7: get value from aws using access_key and secret_access_key and token in an env var
--- config
    location /t {
        content_by_lua_block {
            local aws = require("apisix.secret.aws")
            local conf = {
                endpoint_url = "http://127.0.0.1:4566",
                region = "us-east-1",
                access_key_id = "$ENV://AWS_ACCESS_KEY_ID_LOCAL",
                secret_access_key = "$ENV://AWS_SECRET_ACCESS_KEY_LOCAL",
                session_token = "$ENV://AWS_SESSION_TOKEN_LOCAL",
            }
            local data, err = aws.get(conf, "/apisix-key/jack/key")
            if err then
                return ngx.say(err)
            end
            ngx.say("value")
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 8: get value from aws using access_key and secret_access_key and token in an global env var
--- config
    location /t {
        content_by_lua_block {
            local aws = require("apisix.secret.aws")
            local conf = {
                endpoint_url = "http://127.0.0.1:4566",
            }
            local data, err = aws.get(conf, "/apisix-key/jack/key")
            if err then
                return ngx.say(err)
            end
            ngx.say("value")
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 9: add secret  && consumer && check
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- put secret aws config
            local code, body = t('/apisix/admin/secrets/aws/mysecret',
                ngx.HTTP_PUT,
                [[{
                    "endpoint_url": "http://127.0.0.1:4566",
                    "region": "us-east-1",
                    "access_key_id": "access",
                    "secret_access_key": "secret",
                    "session_token": "token"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            -- change consumer with secrets ref: aws
            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                          "key-auth": {
                            "key": "$secret://aws/mysecret/jack/key"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end


            local secret = require("apisix.secret")
            local value = secret.fetch_by_uri("$secret://aws/mysecret/jack/key")


            local code, body = t('/apisix/admin/secrets/aws/mysecret', ngx.HTTP_DELETE)
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
                            "key": "$secret://aws/mysecret/jack/key"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local secret = require("apisix.secret")
            local value = secret.fetch_by_uri("$secret://aws/mysecret/jack/key")
            ngx.say(value)
        }
    }
--- response_body
nil
