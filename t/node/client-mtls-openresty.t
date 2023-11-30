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
    plan('no_plan');
} else {
    plan(skip_all => "for vanilla OpenResty only");
}

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;
});

run_tests();

__DATA__

=== TEST 1: set verification
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_ca_cert = t.read_file("t/certs/mtls_ca.crt")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1,
                    },
                },
                uri = "/hello"
            }
            assert(t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            ))

            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "localhost",
                client = {
                    ca = ssl_ca_cert,
                    depth = 2,
                }
            }
            local code, body = t.test('/apisix/admin/ssls/1',
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



=== TEST 2: hit
--- exec
curl --cert t/certs/mtls_client.crt --key t/certs/mtls_client.key -k https://localhost:1994/hello
--- response_body
hello world



=== TEST 3: no client certificate
--- exec
curl -k https://localhost:1994/hello
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate was not present



=== TEST 4: wrong client certificate
--- exec
curl --cert t/certs/apisix.crt --key t/certs/apisix.key -k https://localhost:1994/hello
--- response_body eval
qr/400 Bad Request/
--- error_log eval
qr/client certificate verification is not passed: FAILED:self[- ]signed certificate/



=== TEST 5: hit with different host which doesn't require mTLS
--- exec
curl --cert t/certs/mtls_client.crt --key t/certs/mtls_client.key -k https://localhost:1994/hello -H "Host: test.com"
--- response_body
hello world



=== TEST 6: set verification (2 ssl objects)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_ca_cert = t.read_file("t/certs/mtls_ca.crt")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1,
                    },
                },
                uri = "/hello"
            }
            assert(t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            ))

            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "test.com",
                client = {
                    ca = ssl_ca_cert,
                    depth = 2,
                }
            }
            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "localhost",
            }
            local code, body = t.test('/apisix/admin/ssls/2',
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



=== TEST 7: hit without mTLS verify, with Host requires mTLS verification
--- exec
curl -k https://localhost:1994/hello -H "Host: test.com"
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate was not present



=== TEST 8: set verification (2 ssl objects, both have mTLS)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_ca_cert = t.read_file("t/certs/mtls_ca.crt")
            local ssl_ca_cert2 = t.read_file("t/certs/apisix.crt")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1,
                    },
                },
                uri = "/hello"
            }
            assert(t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            ))

            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "localhost",
                client = {
                    ca = ssl_ca_cert,
                    depth = 2,
                }
            }
            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "test.com",
                client = {
                    ca = ssl_ca_cert2,
                    depth = 2,
                }
            }
            local code, body = t.test('/apisix/admin/ssls/2',
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



=== TEST 9: hit with mTLS verify, with Host requires different mTLS verification
--- exec
curl --cert t/certs/mtls_client.crt --key t/certs/mtls_client.key -k https://localhost:1994/hello -H "Host: test.com"
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate verified with SNI localhost, but the host is test.com
