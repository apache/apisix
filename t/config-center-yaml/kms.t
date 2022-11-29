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
  - id: vault/apisix-key
    prefix: kv/prefix
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
  - id: apisix-key
    service: hhh
    prefix: kv/prefix
    token: hvs.GD4458NcXuKqOdEUaaAiuKiR
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



=== TEST 3: normal
--- apisix_yaml
kms:
  - id: vault/apisix-key
    prefix: kv/prefix
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
            ngx.say("service: ", values[1].value.service)
        }
    }
--- request
GET /t
--- response_body
len: 1
id: apisix-key/vault
prefix: kv/prefix
token: root
uri: http://127.0.0.1:8200
service: nil



=== TEST 4: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/apisix-key/bar key=value
--- response_body
Success! Data written to: kv/apisix/apisix-key/bar



=== TEST 5: kms.get: start with $kms://
--- apisix_yaml
kms:
  - id: vault/apisix-key
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.get("$kms://vault/apisix-key/bar/key")
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
  - id: vault/apisix-key
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.get("$KMS://vault/apisix-key/bar/key")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 7: kms.get, wrong ref format: wrong type
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
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.get("$kms://vault/1/")
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
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.get("$kms://vault/1/bar")
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
    prefix: kv/prefix
    token: root
    uri: 127.0.0.1:8200
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



=== TEST 14: kms.get, no sub key
--- apisix_yaml
kms:
  - id: vault/apisix-key
    prefix: kv/apisix
    token: root
    uri: http://127.0.0.1:8200
--- config
    location /t {
        content_by_lua_block {
            local kms = require("apisix.kms")
            local value = kms.get("$kms://vault/apisix-key/bar/test")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil
