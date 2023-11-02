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
    $ENV{VAULT_TOKEN} = "root";
    $ENV{WRONG_VAULT_TOKEN} = "squareroot"
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
            local vault = require("apisix.secret.vault")
            local conf = {
                prefix = "/kv/prefix",
                token = "root",
                uri = "http://127.0.0.1:2800"
            }
            local data, err = vault.get(conf, "apisix")
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
            local vault = require("apisix.secret.vault")
            local conf = {
                prefix = "/kv/prefix",
                token = "root",
                uri = "http://127.0.0.1:2800"
            }
            local data, err = vault.get(conf, "/apisix")
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
            local vault = require("apisix.secret.vault")
            local conf = {
                prefix = "/kv/prefix",
                token = "root",
                uri = "http://127.0.0.1:2800"
            }
            local data, err = vault.get(conf, "apisix/")
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



=== TEST 4: error vault uri
--- config
    location /t {
        content_by_lua_block {
            local vault = require("apisix.secret.vault")
            local conf = {
                prefix = "/kv/prefix",
                token = "root",
                uri = "http://127.0.0.2:2800"
            }
            local data, err = vault.get(conf, "/apisix/sub")
            if err then
                return ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
failed to retrtive data from vault kv engine: connection refused
--- timeout: 6



=== TEST 5: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/apisix-key/jack key=value
--- response_body
Success! Data written to: kv/apisix/apisix-key/jack



=== TEST 6: get value from vault
--- config
    location /t {
        content_by_lua_block {
            local vault = require("apisix.secret.vault")
            local conf = {
                prefix = "kv/apisix",
                token = "root",
                uri = "http://127.0.0.1:8200"
            }
            local value, err = vault.get(conf, "/apisix-key/jack/key")
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



=== TEST 7: get value from vault using token in an env var
--- config
    location /t {
        content_by_lua_block {
            local vault = require("apisix.secret.vault")
            local conf = {
                prefix = "kv/apisix",
                token = "$ENV://VAULT_TOKEN",
                uri = "http://127.0.0.1:8200"
            }
            local value, err = vault.get(conf, "/apisix-key/jack/key")
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



=== TEST 8: get value from vault: token env var wrong/missing
--- config
    location /t {
        content_by_lua_block {
            local vault = require("apisix.secret.vault")
            local conf = {
                prefix = "kv/apisix",
                token = "$ENV://VALT_TOKEN",
                uri = "http://127.0.0.1:8200"
            }
            local value, err = vault.get(conf, "/apisix-key/jack/key")
            if err then
                return ngx.say(err)
            end

            ngx.print("value")
        }
    }
--- request
GET /t
--- response_body_like
failed to decode result, res: \{\"errors\":\[\"permission denied\"\]}\n



=== TEST 9: get value from vault: token env var contains wrong token
--- config
    location /t {
        content_by_lua_block {
            local vault = require("apisix.secret.vault")
            local conf = {
                prefix = "kv/apisix",
                token = "$ENV://WRONG_VAULT_TOKEN",
                uri = "http://127.0.0.1:8200"
            }
            local value, err = vault.get(conf, "/apisix-key/jack/key")
            if err then
                return ngx.say(err)
            end

            ngx.print("value")
        }
    }
--- request
GET /t
--- response_body_like
failed to decode result, res: \{\"errors\":\[\"permission denied\"\]}\n
