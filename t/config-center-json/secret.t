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
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: validate secret/vault: wrong schema
--- apisix_json
{
  "routes": [
    {
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "secrets": [
    {
      "id": "vault/1",
      "prefix": "kv/apisix",
      "token": "root",
      "uri": "127.0.0.1:8200"
    }
  ]
}
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local values = secret.secrets()
            ngx.say(#values)
        }
    }
--- request
GET /t
--- response_body
0
--- error_log
property "uri" validation failed: failed to match pattern "^[^\\/]+:\\/\\/([\\da-zA-Z.-]+|\\[[\\da-fA-F:]+\\])(:\\d+)?"



=== TEST 2: validate secrets: manager not exits
--- apisix_json
{
  "routes": [
    {
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "secrets": [
    {
      "id": "hhh/1",
      "prefix": "kv/apisix",
      "token": "root",
      "uri": "127.0.0.1:8200"
    }
  ]
}
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local values = secret.secrets()
            ngx.say(#values)
        }
    }
--- request
GET /t
--- response_body
0
--- error_log
secret manager not exits



=== TEST 3: load config normal
--- apisix_json
{
  "routes": [
    {
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "secrets": [
    {
      "id": "vault/1",
      "prefix": "kv/apisix",
      "token": "root",
      "uri": "http://127.0.0.1:8200"
    }
  ]
}
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local values = secret.secrets()
            ngx.say("len: ", #values)

            ngx.say("id: ", values[1].value.id)
            ngx.say("prefix: ", values[1].value.prefix)
            ngx.say("token: ", values[1].value.token)
            ngx.say("uri: ", values[1].value.uri)
        }
    }
--- request
GET /t
--- response_body
len: 1
id: vault/1
prefix: kv/apisix
token: root
uri: http://127.0.0.1:8200



=== TEST 4: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/apisix-key key=value
--- response_body
Success! Data written to: kv/apisix/apisix-key



=== TEST 5: secret.fetch_by_uri: start with $secret://
--- apisix_json
{
  "routes": [
    {
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "secrets": [
    {
      "id": "vault/1",
      "prefix": "kv/apisix",
      "token": "root",
      "uri": "http://127.0.0.1:8200"
    }
  ]
}
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local value = secret.fetch_by_uri("$secret://vault/1/apisix-key/key")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 6: secret.fetch_by_uri, wrong ref format: wrong type
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local _, err = secret.fetch_by_uri(1)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error secret_uri type: number



=== TEST 7: secret.fetch_by_uri, wrong ref format: wrong prefix
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local _, err = secret.fetch_by_uri("secret://")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error secret_uri prefix: secret://



=== TEST 8: secret.fetch_by_uri, error format: no secret manager
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local _, err = secret.fetch_by_uri("$secret://")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error format: no secret manager



=== TEST 9: secret.fetch_by_uri, error format: no secret conf id
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local _, err = secret.fetch_by_uri("$secret://vault/")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error format: no secret conf id



=== TEST 10: secret.fetch_by_uri, error format: no secret key id
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local _, err = secret.fetch_by_uri("$secret://vault/2/")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error format: no secret key id



=== TEST 11: secret.fetch_by_uri, no config
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local _, err = secret.fetch_by_uri("$secret://vault/2/bar")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
no secret conf, secret_uri: $secret://vault/2/bar



=== TEST 12: secret.fetch_by_uri, no sub key value
--- apisix_json
{
  "routes": [
    {
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "secrets": [
    {
      "id": "vault/1",
      "prefix": "kv/apisix",
      "token": "root",
      "uri": "http://127.0.0.1:8200"
    }
  ]
}
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local value = secret.fetch_by_uri("$secret://vault/1/apisix-key/bar")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil



=== TEST 13: fetch_secrets env: no cache
--- main_config
env secret=apisix;
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local refs = {
                key = "jack",
                secret = "$env://secret"
            }
            local new_refs = secret.fetch_secrets(refs)
            assert(new_refs ~= refs)
            ngx.say(refs.secret)
            ngx.say(new_refs.secret)
            ngx.say(new_refs.key)
        }
    }
--- request
GET /t
--- response_body
$env://secret
apisix
jack
--- error_log_like
qr/retrieve secrets refs/



=== TEST 14: fetch_secrets env: cache
--- main_config
env secret=apisix;
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local refs = {
                key = "jack",
                secret = "$env://secret"
            }
            local refs_1 = secret.fetch_secrets(refs, true, "key", 1)
            local refs_2 = secret.fetch_secrets(refs, true, "key", 1)
            assert(refs_1 == refs_2)
            ngx.say(refs_1.secret)
            ngx.say(refs_2.secret)
        }
    }
--- request
GET /t
--- response_body
apisix
apisix
--- grep_error_log eval
qr/retrieve secrets refs/
--- grep_error_log_out
retrieve secrets refs



=== TEST 15: fetch_secrets env: table nesting
--- main_config
env secret=apisix;
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local refs = {
                key = "jack",
                user = {
                    username = "apisix",
                    passsword = "$env://secret"
                }
            }
            local new_refs = secret.fetch_secrets(refs)
            ngx.say(new_refs.user.passsword)
        }
    }
--- request
GET /t
--- response_body
apisix



=== TEST 16: fetch_secrets: wrong refs type
--- main_config
env secret=apisix;
--- config
    location /t {
        content_by_lua_block {
            local secret = require("apisix.secret")
            local refs = "wrong"
            local new_refs = secret.fetch_secrets(refs)
            ngx.say(new_refs)
        }
    }
--- request
GET /t
--- response_body
nil
