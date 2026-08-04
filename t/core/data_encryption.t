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

repeat_each(2);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: 16 byte key builds an AES-128 cipher and round-trips
--- config
    location /t {
        content_by_lua_block {
            local data_encryption = require("apisix.core.data_encryption")
            local iv_tbl = data_encryption.init_iv_tbl("qeddd145sfvddff3")
            ngx.say("ciphers: ", #iv_tbl)

            local enc = data_encryption.aes_cbc_encrypt(iv_tbl, "hello world")
            ngx.say("encrypted differs: ", enc ~= "hello world")
            ngx.say("decrypted: ", data_encryption.aes_cbc_decrypt(iv_tbl, enc))
        }
    }
--- request
GET /t
--- response_body
ciphers: 1
encrypted differs: true
decrypted: hello world
--- no_error_log
[error]



=== TEST 2: 32 byte key builds an AES-256 cipher and round-trips
--- config
    location /t {
        content_by_lua_block {
            local data_encryption = require("apisix.core.data_encryption")
            local iv_tbl = data_encryption.init_iv_tbl("qeddd145sfvddff3qeddd145sfvddff3")
            ngx.say("ciphers: ", #iv_tbl)

            local enc = data_encryption.aes_cbc_encrypt(iv_tbl, "hello world")
            ngx.say("encrypted differs: ", enc ~= "hello world")
            ngx.say("decrypted: ", data_encryption.aes_cbc_decrypt(iv_tbl, enc))
        }
    }
--- request
GET /t
--- response_body
ciphers: 1
encrypted differs: true
decrypted: hello world
--- no_error_log
[error]



=== TEST 3: rotating an AES-128 keyring to AES-256 keeps the old data readable
--- config
    location /t {
        content_by_lua_block {
            local data_encryption = require("apisix.core.data_encryption")

            -- data written before the rotation, encrypted with the 16 byte key only
            local legacy = data_encryption.init_iv_tbl("qeddd145sfvddff3")
            local legacy_enc = data_encryption.aes_cbc_encrypt(legacy, "hello world")

            -- the new 32 byte key goes first, the old one is kept to read old data
            local rotated = data_encryption.init_iv_tbl({
                "qeddd145sfvddff3qeddd145sfvddff3",
                "qeddd145sfvddff3",
            })
            ngx.say("ciphers: ", #rotated)
            ngx.say("legacy data: ", data_encryption.aes_cbc_decrypt(rotated, legacy_enc))

            -- new writes go through the first (AES-256) cipher
            local enc = data_encryption.aes_cbc_encrypt(rotated, "hello world")
            ngx.say("re-encrypted: ", enc ~= legacy_enc)
            ngx.say("new data: ", data_encryption.aes_cbc_decrypt(rotated, enc))
        }
    }
--- request
GET /t
--- response_body
ciphers: 2
legacy data: hello world
re-encrypted: true
new data: hello world
--- no_error_log
[error]



=== TEST 4: a key of an unsupported length is dropped and reported
--- config
    location /t {
        content_by_lua_block {
            local data_encryption = require("apisix.core.data_encryption")
            local iv_tbl = data_encryption.init_iv_tbl({
                "short",
                "qeddd145sfvddff3",
            })
            ngx.say("ciphers: ", #iv_tbl)
        }
    }
--- request
GET /t
--- response_body
ciphers: 1
--- error_log
expected a 16 byte (AES-128) or 32 byte (AES-256) key, got 5 bytes



=== TEST 5: a 32 byte keyring configured in config.yaml encrypts and decrypts
--- yaml_config
apisix:
    node_listen: 1984
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local data_encryption = require("apisix.core.data_encryption")
            local enc = data_encryption.encrypt("hello world")
            ngx.say("encrypted: ", enc ~= "hello world")
            ngx.say("decrypted: ", data_encryption.decrypt(enc))
        }
    }
--- request
GET /t
--- response_body
encrypted: true
decrypted: hello world
--- no_error_log
[error]
