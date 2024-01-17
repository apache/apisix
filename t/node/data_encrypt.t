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
});

run_tests;

__DATA__

=== TEST 1: sanity
# the sensitive data is encrypted in etcd, and it is normal to read it from the admin API
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/consumers/foo',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["basic-auth"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/foo'))
            ngx.say(res.body.node.value.plugins["basic-auth"].password)

        }
    }
--- response_body
bar
77+NmbYqNfN+oLm0aX5akg==



=== TEST 2: enable basic auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: verify
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world



=== TEST 4: multiple auth plugins work well
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        },
                        "key-auth": {
                            "key": "auth-one"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)
            local code, message, res = t('/apisix/admin/consumers/foo',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 5: enable multiple auth plugins on route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {},
                        "key-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: verify
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- request
GET /hello
--- more_headers
apikey: auth-one
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world



=== TEST 7: disable data_encryption
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: false
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/foo'))
            ngx.say(res.body.node.value.plugins["basic-auth"].password)

        }
    }
--- response_body
bar



=== TEST 8: etcd store unencrypted password, enable data_encryption, decryption fails, use original password
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res, err = core.etcd.set("/consumers/foo2", core.json.decode([[{
                "username":"foo2",
                "plugins":{
                    "basic-auth":{
                        "username":"foo2",
                        "password":"bar"
                    }
                }
            }]]))

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/consumers/foo2',
                ngx.HTTP_GET
            )
            res = core.json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["basic-auth"].password)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/foo2'))
            ngx.say(res.body.node.value.plugins["basic-auth"].password)
        }
    }
--- response_body
bar
bar
--- error_log
failed to decrypt the conf of plugin [basic-auth] key [password], err: decrypt ssl key failed



=== TEST 9: etcd stores both encrypted and unencrypted data
# enable data_encryption, decryption of encrypted data succeeds
# decryption of unencrypted data fails, make sure it works well
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")
            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res, err = core.etcd.set("/consumers/foo2", core.json.decode([[{
                "username":"foo2",
                "plugins":{
                    "basic-auth":{
                        "username":"foo2",
                        "password":"bar"
                    },
                    "key-auth": {
                        "key": "vU/ZHVJw7b0XscDJ1Fhtig=="
                    }
                }
            }]]))

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/consumers/foo2',
                ngx.HTTP_GET
            )
            res = core.json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["basic-auth"].password)
            ngx.say(res.value.plugins["key-auth"].key)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/foo2'))
            ngx.say(res.body.node.value.plugins["basic-auth"].password)
            ngx.say(res.body.node.value.plugins["key-auth"].key)
        }
    }
--- response_body
bar
auth-two
bar
vU/ZHVJw7b0XscDJ1Fhtig==
--- error_log
failed to decrypt the conf of plugin [basic-auth] key [password], err: decrypt ssl key failed



=== TEST 10: verify, use the foo2 consumer
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- request
GET /hello
--- more_headers
apikey: auth-two
Authorization: Basic Zm9vMjpiYXI=
--- response_body
hello world



=== TEST 11: keyring rotate, encrypt with edd1c9f0985e76a2
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "basic-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: keyring rotate, decrypt with edd1c9f0985e76a2 would fail, but encrypt with edd1c9f0985e76a2 would success
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
            - edd1c9f0985e76a2
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world



=== TEST 13: search consumer list
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            -- dletet exist consumers
            t('/apisix/admin/consumers/foo', ngx.HTTP_DELETE)
            t('/apisix/admin/consumers/foo2', ngx.HTTP_DELETE)

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "test",
                    "plugins": {
                        "basic-auth": {
                            "username": "test",
                            "password": "test"
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/consumers',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            local pwds = {}
            table.insert(pwds, res.list[1].value.plugins["basic-auth"].password)
            table.insert(pwds, res.list[2].value.plugins["basic-auth"].password)

            ngx.say(json.encode(pwds))
        }
    }
--- response_body
["bar","test"]
