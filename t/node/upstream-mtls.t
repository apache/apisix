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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: tls without key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1983"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                    }
                },
                uri = "/hello"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream\" validation failed: property \"tls\" validation failed: property \"client_key\" is required"}



=== TEST 2: tls with bad key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1983"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ("AAA"):rep(128),
                    }
                },
                uri = "/hello"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to decrypt previous encrypted key"}
--- error_log
decrypt ssl key failed



=== TEST 3: encrypt key by default
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1983"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key,
                    }
                },
                uri = "/hello"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, res = t.test('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            res = json.decode(res)
            ngx.say(res.node.value.upstream.tls.client_key == ssl_key)

            -- upstream
            local data = {
                scheme = "https",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1983"] = 1,
                },
                tls = {
                    client_cert = ssl_cert,
                    client_key = ssl_key,
                }
            }
            local code, body = t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, res = t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            res = json.decode(res)
            ngx.say(res.node.value.tls.client_key == ssl_key)

            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1983"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key,
                    }
                },
            }
            local code, body = t.test('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, res = t.test('/apisix/admin/services/1',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            res = json.decode(res)
            ngx.say(res.node.value.upstream.tls.client_key == ssl_key)
        }
    }
--- request
GET /t
--- response_body
false
false
false



=== TEST 4: hit
--- upstream_server_config
    ssl_client_certificate ../../certs/mtls_ca.crt;
    ssl_verify_client on;
--- request
GET /hello
--- response_body
hello world



=== TEST 5: wrong cert
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key = t.read_file("t/certs/apisix.key")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1983"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key,
                    }
                },
                uri = "/hello"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
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



=== TEST 6: hit
--- upstream_server_config
    ssl_client_certificate ../../certs/mtls_ca.crt;
    ssl_verify_client on;
--- request
GET /hello
--- error_code: 400
--- error_log
client SSL certificate verify error



=== TEST 7: clean old data
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            assert(t.test('/apisix/admin/routes/1',
                ngx.HTTP_DELETE
            ))
            assert(t.test('/apisix/admin/services/1',
                ngx.HTTP_DELETE
            ))
            assert(t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_DELETE
            ))
        }
    }
--- request
GET /t



=== TEST 8: don't encrypt key
--- yaml_config
apisix:
    node_listen: 1984
    admin_key: null
    ssl:
        key_encrypt_salt: null
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1983"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key,
                    }
                },
                uri = "/hello"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, res = t.test('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            res = json.decode(res)
            ngx.say(res.node.value.upstream.tls.client_key == ssl_key)

            -- upstream
            local data = {
                scheme = "https",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1983"] = 1,
                },
                tls = {
                    client_cert = ssl_cert,
                    client_key = ssl_key,
                }
            }
            local code, body = t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, res = t.test('/apisix/admin/upstreams/1',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            res = json.decode(res)
            ngx.say(res.node.value.tls.client_key == ssl_key)

            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1983"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key,
                    }
                },
            }
            local code, body = t.test('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body, res = t.test('/apisix/admin/services/1',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            res = json.decode(res)
            ngx.say(res.node.value.upstream.tls.client_key == ssl_key)
        }
    }
--- request
GET /t
--- response_body
true
true
true



=== TEST 9: bind upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local data = {
                upstream_id = 1,
                uri = "/server_port"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        }
    }
--- request
GET /t



=== TEST 10: hit
--- upstream_server_config
    ssl_client_certificate ../../certs/mtls_ca.crt;
    ssl_verify_client on;
--- request
GET /server_port
--- response_body chomp
1983



=== TEST 11: bind service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local data = {
                service_id = 1,
                uri = "/hello_chunked"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        }
    }
--- request
GET /t



=== TEST 12: hit
--- upstream_server_config
    ssl_client_certificate ../../certs/mtls_ca.crt;
    ssl_verify_client on;
--- request
GET /hello_chunked
--- response_body
hello world
