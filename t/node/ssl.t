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
    sub set_env_from_file {
        my ($env_name, $file_path) = @_;

        open my $fh, '<', $file_path or die $!;
        my $content = do { local $/; <$fh> };
        close $fh;

        $ENV{$env_name} = $content;
    }
    # set env
    set_env_from_file('TEST_CERT', 't/certs/apisix.crt');
    set_env_from_file('TEST_KEY', 't/certs/apisix.key');
    set_env_from_file('TEST2_CERT', 't/certs/test2.crt');
    set_env_from_file('TEST2_KEY', 't/certs/test2.key');
}

use t::APISIX 'no_plan';

log_level('info');
no_root_location();

sub set_env_from_file {
    my ($env_name, $file_path) = @_;

    open my $fh, '<', $file_path or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;

    $ENV{$env_name} = $content;
}


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests;

__DATA__

=== TEST 1: store two certs and keys in vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/ssl \
    test.com.crt=@t/certs/apisix.crt \
    test.com.key=@t/certs/apisix.key \
    test.com.2.crt=@t/certs/test2.crt \
    test.com.2.key=@t/certs/test2.key
--- response_body
Success! Data written to: kv/apisix/ssl



=== TEST 2: set secret
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/vault/test',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://0.0.0.0:8200",
                    "prefix": "kv/apisix",
                    "token": "root"
                }]],
                [[{
                    "key": "/apisix/secrets/vault/test",
                    "value": {
                        "uri": "http://0.0.0.0:8200",
                        "prefix": "kv/apisix",
                        "token": "root"
                    }
                }]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: set ssl with two certs and keys in vault
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                snis = {"test.com"},
                key =  "$secret://vault/test/ssl/test.com.key",
                cert = "$secret://vault/test/ssl/test.com.crt",
                keys = {"$secret://vault/test/ssl/test.com.2.key"},
                certs = {"$secret://vault/test/ssl/test.com.2.crt"}
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "snis": ["test.com"],
                        "key": "$secret://vault/test/ssl/test.com.key",
                        "cert": "$secret://vault/test/ssl/test.com.crt",
                        "keys": ["$secret://vault/test/ssl/test.com.2.key"],
                        "certs": ["$secret://vault/test/ssl/test.com.2.crt"]
                    },
                    "key": "/apisix/ssls/1"
                }]]
              )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
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
--- request
GET /t
--- response_body
passed



=== TEST 5: access to https with test.com
--- exec
curl -s -k https://test.com:1994/hello
--- response_body
hello world
--- error_log
fetching data from secret uri
fetching data from secret uri
fetching data from secret uri
fetching data from secret uri



=== TEST 6: set ssl with two certs and keys in env
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local data = {
                snis = {"test.com"},
                key =  "$env://TEST_KEY",
                cert = "$env://TEST_CERT",
                keys = {"$env://TEST2_KEY"},
                certs = {"$env://TEST2_CERT"}
            }

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "snis": ["test.com"],
                        "key": "$env://TEST_KEY",
                        "cert": "$env://TEST_CERT",
                        "keys": ["$env://TEST2_KEY"],
                        "certs": ["$env://TEST2_CERT"]
                    },
                    "key": "/apisix/ssls/1"
                }]]
              )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: access to https with test.com
--- exec
curl -s -k https://test.com:1994/hello
--- response_body
hello world
--- error_log
fetching data from env uri
fetching data from env uri
fetching data from env uri
fetching data from env uri
