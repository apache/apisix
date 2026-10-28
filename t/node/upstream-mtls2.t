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
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->http_config) {
        my $http_config = <<'_EOC_';

proxy_ssl_trusted_certificate ../../certs/mtls_ca.crt;
proxy_ssl_verify on;

server {
    listen 8777 ssl;
    ssl_certificate ../../certs/mtls_server.crt;
    ssl_certificate_key ../../certs/mtls_server.key;
    ssl_client_certificate ../../certs/mtls_ca.crt;
    ssl_verify_client on;

    location /hello {
        return 200 'ok\n';
    }
}

_EOC_
        $block->set_value("http_config", $http_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: reject a ca_certs entry that isn't a certificate
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:8777"] = 1,
                    },
                    tls = {
                        client_cert = t.read_file("t/certs/mtls_client.crt"),
                        client_key = t.read_file("t/certs/mtls_client.key"),
                        verify = true,
                        ca_certs = {string.rep("not a certificate", 16)},
                    }
                },
                uri = "/hello"
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to parse cert: PEM_read_bio_X509_AUX() failed"}



=== TEST 2: verify against the CA trusted by nginx
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:8777"] = 1,
                    },
                    tls = {
                        client_cert = t.read_file("t/certs/mtls_client.crt"),
                        client_key = t.read_file("t/certs/mtls_client.key"),
                        verify = true,
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
--- response_body
passed



=== TEST 3: verification passes for the SNI the certificate is issued for
--- request
GET /hello
--- more_headers
host: admin.apisix.dev
--- response_body
ok



=== TEST 4: verification rejects a certificate that doesn't match the SNI
--- request
GET /hello
--- more_headers
host: invalid.apisix.dev
--- error_code: 502
--- error_log
upstream SSL certificate does not match "invalid.apisix.dev"



=== TEST 5: ca_certs replaces the CA trusted by nginx
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:8777"] = 1,
                    },
                    tls = {
                        client_cert = t.read_file("t/certs/mtls_client.crt"),
                        client_key = t.read_file("t/certs/mtls_client.key"),
                        verify = true,
                        ca_certs = {t.read_file("t/certs/apisix.crt")},
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
--- response_body
passed



=== TEST 6: the upstream certificate no longer chains to a trusted CA
--- request
GET /hello
--- more_headers
host: admin.apisix.dev
--- error_code: 502
--- error_log
upstream SSL certificate verify error: (21:unable to verify the first certificate)



=== TEST 7: turning verification off ignores ca_certs
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:8777"] = 1,
                    },
                    tls = {
                        client_cert = t.read_file("t/certs/mtls_client.crt"),
                        client_key = t.read_file("t/certs/mtls_client.key"),
                        verify = false,
                        ca_certs = {t.read_file("t/certs/apisix.crt")},
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
--- response_body
passed



=== TEST 8: request succeeds despite the untrusted CA
--- request
GET /hello
--- more_headers
host: admin.apisix.dev
--- response_body
ok



=== TEST 9: verify against a CA given in ca_certs
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:8777"] = 1,
                    },
                    tls = {
                        client_cert = t.read_file("t/certs/mtls_client.crt"),
                        client_key = t.read_file("t/certs/mtls_client.key"),
                        verify = true,
                        ca_certs = {t.read_file("t/certs/mtls_ca.crt")},
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
--- response_body
passed



=== TEST 10: request succeeds
--- request
GET /hello
--- more_headers
host: admin.apisix.dev
--- response_body
ok



=== TEST 11: any CA in ca_certs can anchor the chain
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local data = {
                upstream = {
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:8777"] = 1,
                    },
                    tls = {
                        client_cert = t.read_file("t/certs/mtls_client.crt"),
                        client_key = t.read_file("t/certs/mtls_client.key"),
                        verify = true,
                        ca_certs = {
                            t.read_file("t/certs/apisix.crt"),
                            t.read_file("t/certs/mtls_ca.crt"),
                        },
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
--- response_body
passed



=== TEST 12: request succeeds
--- request
GET /hello
--- more_headers
host: admin.apisix.dev
--- response_body
ok
