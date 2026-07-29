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



=== TEST 3: a 16 and a 32 byte key coexist in one keyring
--- config
    location /t {
        content_by_lua_block {
            local data_encryption = require("apisix.core.data_encryption")
            local iv_tbl = data_encryption.init_iv_tbl({
                "qeddd145sfvddff3qeddd145sfvddff3",
                "qeddd145sfvddff3",
            })
            ngx.say("ciphers: ", #iv_tbl)

            -- encrypt with the first (AES-256) cipher
            local enc = data_encryption.aes_cbc_encrypt(iv_tbl, "hello world")
            -- decrypt tries every cipher in the keyring, so it still resolves
            ngx.say("decrypted: ", data_encryption.aes_cbc_decrypt(iv_tbl, enc))
        }
    }
--- request
GET /t
--- response_body
ciphers: 2
decrypted: hello world
--- no_error_log
[error]



=== TEST 4: a key of an unsupported length is skipped
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
--- no_error_log
[error]
