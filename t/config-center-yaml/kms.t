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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    if (!$block->apisix_yaml) {
        my $routes = <<_EOC_;
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
_EOC_

        $block->set_value("apisix_yaml", $routes);
    }

});

run_tests();

__DATA__

=== TEST 1: validate kms/vault: wrong schema
--- apisix_yaml
kms:
  - id: vault/1
    prefix: kv/apisix
    token: root
    uri: 127.0.0.1:8200
#END
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local values = kms.kmss()
            ngx.say(#values)
        }
    }
--- request
GET /t
--- response_body
0
--- error_log
property "uri" validation failed: failed to match pattern "^[^\\/]+:\\/\\/([\\da-zA-Z.-]+|\\[[\\da-fA-F:]+\\])(:\\d+)?"



=== TEST 2: validate kms: service not exits
--- apisix_yaml
kms:
  - id: hhh/1
    prefix: kv/apisix
    token: root
    uri: 127.0.0.1:8200
#END
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local values = kms.kmss()
            ngx.say(#values)
        }
    }
--- request
GET /t
--- response_body
0
--- error_log
kms service not exits



=== TEST 3: load config normal
--- apisix_yaml
kms:
  - id: vault/1
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
#END
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local values = kms.kmss()
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



=== TEST 5: kms.fetch_by_uri: start with $kms://
--- apisix_yaml
kms:
  - id: vault/1
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
#END
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.fetch_by_uri("$kms://vault/1/apisix-key/key")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 6: kms.fetch_by_uri: start with $KMS://
--- apisix_yaml
kms:
  - id: vault/1
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
#END
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.fetch_by_uri("$KMS://vault/1/apisix-key/key")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 7: kms.fetch_by_uri, wrong ref format: wrong type
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local _, err = kms.fetch_by_uri(1)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error kms_uri type: number



=== TEST 8: kms.fetch_by_uri, wrong ref format: wrong prefix
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local _, err = kms.fetch_by_uri("kms://")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error kms_uri prefix: kms://



=== TEST 9: kms.fetch_by_uri, error format: no kms service
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local _, err = kms.fetch_by_uri("$kms://")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error format: no kms service



=== TEST 10: kms.fetch_by_uri, error format: no kms conf id
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local _, err = kms.fetch_by_uri("$kms://vault/")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error format: no kms conf id



=== TEST 11: kms.fetch_by_uri, error format: no kms key id
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local _, err = kms.fetch_by_uri("$kms://vault/2/")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error format: no kms key id



=== TEST 12: kms.fetch_by_uri, no config
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local _, err = kms.fetch_by_uri("$kms://vault/2/bar")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
no kms conf, kms_uri: $kms://vault/2/bar



=== TEST 13: kms.fetch_by_uri, no sub key value
--- apisix_yaml
kms:
  - id: vault/1
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
#END
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.fetch_by_uri("$kms://vault/1/apisix-key/bar")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil



=== TEST 14: fetch_secrets env: no cache
--- main_config
env secret=apisix;
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local refs = {
                key = "jack",
                secret = "$env://secret"
            }
            local new_refs = kms.fetch_secrets(refs)
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



=== TEST 15: fetch_secrets env: cache
--- main_config
env secret=apisix;
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local refs = {
                key = "jack",
                secret = "$env://secret"
            }
            local refs_1 = kms.fetch_secrets(refs, true, "key", 1)
            local refs_2 = kms.fetch_secrets(refs, true, "key", 1)
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



=== TEST 16: fetch_secrets env: table nesting
--- main_config
env secret=apisix;
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local refs = {
                key = "jack",
                user = {
                    username = "apisix",
                    passsword = "$env://secret"
                }
            }
            local new_refs = kms.fetch_secrets(refs)
            ngx.say(new_refs.user.passsword)
        }
    }
--- request
GET /t
--- response_body
apisix



=== TEST 17: fetch_secrets: wrong refs type
--- main_config
env secret=apisix;
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local refs = "wrong"
            local new_refs = kms.fetch_secrets(refs)
            ngx.say(new_refs)
        }
    }
--- request
GET /t
--- response_body
nil
