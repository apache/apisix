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
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: not unwanted data, POST
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "not-unwanted-post.com"}
            local code, message, res = t.test('/apisix/admin/ssl',
                ngx.HTTP_POST,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            res.node.key = nil
            res.node.value.create_time = nil
            res.node.value.update_time = nil
            res.node.value.cert = ""
            res.node.value.key = ""
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"create","node":{"value":{"cert":"","key":"","sni":"not-unwanted-post.com","status":1}}}



=== TEST 2: not unwanted data, PUT
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            res.node.value.create_time = nil
            res.node.value.update_time = nil
            res.node.value.cert = ""
            res.node.value.key = ""
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"set","node":{"key":"/apisix/ssl/1","value":{"cert":"","id":"1","key":"","sni":"test.com","status":1}}}



=== TEST 3: not unwanted data, PATCH
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "t.com"}
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PATCH,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            res.node.value.create_time = nil
            res.node.value.update_time = nil
            res.node.value.cert = ""
            res.node.value.key = ""
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"compareAndSwap","node":{"key":"/apisix/ssl/1","value":{"cert":"","id":"1","key":"","sni":"t.com","status":1}}}



=== TEST 4: not unwanted data, GET
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            local value = res.node.value
            assert(value.create_time ~= nil)
            value.create_time = nil
            assert(value.update_time ~= nil)
            value.update_time = nil
            assert(value.cert ~= nil)
            value.cert = ""
            assert(value.key == nil)
            assert(res.count ~= nil)
            res.count = nil
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"get","node":{"key":"/apisix/ssl/1","value":{"cert":"","id":"1","sni":"t.com","status":1}}}



=== TEST 5: not unwanted data, DELETE
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_DELETE
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            ngx.say(json.encode(res))
        }
    }
--- response_body
{"action":"delete","deleted":"1","key":"/apisix/ssl/1","node":{}}



=== TEST 6: bad cert
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = [[-----BEGIN CERTIFICATE-----
MIIEojCCAwqgAwIBAgIJAK253pMhgCkxMA0GCSqGSIb3DQEBCwUAMFYxCzAJBgNV
BAYTAkNOMRIwEAYDVQQIDAlHdWFuZ0RvbmcxDzANBgNVBAcMBlpodUhhaTEPMA0G
U/OOcSRr39Kuis/JJ+DkgHYa/PWHZhnJQBxcqXXk1bJGw9BNbhM=
-----END CERTIFICATE-----
            ]], key = ssl_key, sni = "test.com"}
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say(res)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to parse cert: PEM_read_bio_X509_AUX() failed"}



=== TEST 7: bad key
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local data = {cert = ssl_cert, key = [[
-----BEGIN RSA PRIVATE KEY-----
MIIG5AIBAAKCAYEAyCM0rqJecvgnCfOw4fATotPwk5Ba0gC2YvIrO+gSbQkyxXF5
jhZB3W6BkWUWR4oNFLLSqcVbVDPitz/Mt46Mo8amuS6zTbQetGnBARzPLtmVhJfo
wzarryret/7GFW1/3cz+hTj9/d45i25zArr3Pocfpur5mfz3fJO8jg==
-----END RSA PRIVATE KEY-----]], sni = "test.com"}
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say(res)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to parse key: PEM_read_bio_PrivateKey() failed"}



=== TEST 8: bad certs
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "t.com",
                certs = {
                    [[-----BEGIN CERTIFICATE-----
MIIEojCCAwqgAwIBAgIJAK253pMhgCkxMA0GCSqGSIb3DQEBCwUAMFYxCzAJBgNV
BAYTAkNOMRIwEAYDVQQIDAlHdWFuZ0RvbmcxDzANBgNVBAcMBlpodUhhaTEPMA0G
U/OOcSRr39Kuis/JJ+DkgHYa/PWHZhnJQBxcqXXk1bJGw9BNbhM=
-----END CERTIFICATE-----]]
                },
                keys = {ssl_key}
            }
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say(res)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to handle cert-key pair[1]: failed to parse cert: PEM_read_bio_X509_AUX() failed"}



=== TEST 9: bad keys
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "t.com",
                certs = {ssl_cert},
                keys = {[[-----BEGIN RSA PRIVATE KEY-----
MIIG5AIBAAKCAYEAyCM0rqJecvgnCfOw4fATotPwk5Ba0gC2YvIrO+gSbQkyxXF5
jhZB3W6BkWUWR4oNFLLSqcVbVDPitz/Mt46Mo8amuS6zTbQetGnBARzPLtmVhJfo
wzarryret/7GFW1/3cz+hTj9/d45i25zArr3Pocfpur5mfz3fJO8jg==
-----END RSA PRIVATE KEY-----]]}
            }
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say(res)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to handle cert-key pair[1]: failed to parse key: PEM_read_bio_PrivateKey() failed"}



=== TEST 10: empty snis
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, snis = {}}
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say(res)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"snis\" validation failed: expect array to have at least 1 items"}



=== TEST 11: update snis, PATCH with sub path
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, snis = {"test.com"}}
            local code, message, res = t.test('/apisix/admin/ssl/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end


            local data = {"update1.com", "update2.com"}
            local code, message, res = t.test('/apisix/admin/ssl/1/snis',
                ngx.HTTP_PATCH,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            ngx.say(res)
        }
    }
--- response_body_like eval
qr/"snis":\["update1.com","update2.com"\]/
