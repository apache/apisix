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
--- apisix_yaml
kms:
  - id: vault/1
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
#END
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/apisix-key key=value
--- response_body
Success! Data written to: kv/apisix/apisix-key



=== TEST 5: kms.get: start with $kms://
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
            local value = kms.get("$kms://vault/1/apisix-key/key")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 6: kms.get: start with $KMS://
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
            local value = kms.get("$KMS://vault/1/apisix-key/key")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 7: kms.get, wrong ref format: wrong type
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
            local value = kms.get(1)
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil



=== TEST 8: kms.get, wrong ref format: wrong prefix
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
            local value = kms.get("kms://")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil



=== TEST 9: kms.get, error format: no kms service
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
            local value = kms.get("$kms://")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil
--- error_log
error format: no kms service



=== TEST 10: kms.get, error format: no kms conf id
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
            local value = kms.get("$kms://vault/")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil
--- error_log
error format: no kms conf id



=== TEST 11: kms.get, error format: no kms key id
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
            local value = kms.get("$kms://vault/2/")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil
--- error_log
error format: no kms key id



=== TEST 12: kms.get, no config
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
            local value = kms.get("$kms://vault/2/bar")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil
--- error_log
no config



=== TEST 13: kms.get, no kms service
--- apisix_yaml
kms:
  - id: vault/apisix-key
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
#END
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.get("$kms://dummy/1/bar")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil
--- error_log
no config



=== TEST 14: kms.get, no sub key value
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
            local value = kms.get("$kms://vault/1/apisix-key/bar")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil
