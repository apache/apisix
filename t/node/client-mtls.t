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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

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
});

run_tests();

__DATA__

=== TEST 1: bad client certificate
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "test.com",
                client = {
                    ca = ("test.com"):rep(128),
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
--- error_code: 400
--- response_body
{"error_msg":"failed to validate client_cert: failed to parse cert: PEM_read_bio_X509_AUX() failed"}



=== TEST 2: missing client certificate
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "test.com",
                client = {
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
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"client\" validation failed: property \"ca\" is required"}



=== TEST 3: set verification
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
                    scheme = "https",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1994"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key,
                    }
                },
                plugins = {
                    ["proxy-rewrite"] = {
                        uri = "/hello"
                    }
                },
                uri = "/mtls"
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

            local data = {
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1,
                    },
                },
                uri = "/hello"
            }
            assert(t.test('/apisix/admin/routes/2',
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



=== TEST 4: hit
--- request
GET /mtls
--- more_headers
Host: localhost
--- response_body
hello world



=== TEST 5: no client certificate
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
                        ["127.0.0.1:1994"] = 1,
                    },
                },
                plugins = {
                    ["proxy-rewrite"] = {
                        uri = "/hello"
                    }
                },
                uri = "/mtls2"
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

            ngx.print(body)
        }
    }
--- request
GET /t



=== TEST 6: hit
--- request
GET /mtls2
--- more_headers
Host: localhost
--- error_code: 502
--- error_log
peer did not return a certificate



=== TEST 7: wrong client certificate
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
                        ["127.0.0.1:1994"] = 1,
                    },
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key,
                    }
                },
                plugins = {
                    ["proxy-rewrite"] = {
                        uri = "/hello"
                    }
                },
                uri = "/mtls3"
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

            ngx.print(body)
        }
    }
--- request
GET /t



=== TEST 8: hit
--- request
GET /mtls3
--- more_headers
Host: localhost
--- error_code: 502
--- error_log
certificate verify failed



=== TEST 9: set verification
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



=== TEST 10: hit with different host which doesn't require mTLS
--- exec
curl --cert t/certs/mtls_client.crt --key t/certs/mtls_client.key -k https://localhost:1994/hello -H "Host: x.com"
--- response_body
hello world



=== TEST 11: set verification (2 ssl objects)
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



=== TEST 12: hit without mTLS verify, with Host requires mTLS verification
--- exec
curl -k https://localhost:1994/hello -H "Host: test.com"
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate verified with SNI localhost, but the host is test.com



=== TEST 13: set verification (2 ssl objects, both have mTLS)
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



=== TEST 14: hit with mTLS verify, with Host requires different mTLS verification
--- exec
curl --cert t/certs/mtls_client.crt --key t/certs/mtls_client.key -k https://localhost:1994/hello -H "Host: test.com"
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate verified with SNI localhost, but the host is test.com



=== TEST 15: request localhost and save tls session to reuse
--- max_size: 1048576
--- exec
echo "GET /hello HTTP/1.1\r\nHost: localhost\r\n" | \
    timeout 1 openssl s_client -ign_eof -connect 127.0.0.1:1994 \
    -servername localhost -cert t/certs/mtls_client.crt -key t/certs/mtls_client.key \
    -sess_out session.dat || true
--- response_body eval
qr/200 OK/



=== TEST 16: request test.com with saved tls session
--- max_size: 1048576
--- exec
echo "GET /hello HTTP/1.1\r\nHost: test.com\r\n" | \
    openssl s_client -ign_eof -connect 127.0.0.1:1994 -servername test.com \
    -sess_in session.dat
--- response_body eval
qr/400 Bad Request/
--- error_log
sni in client hello mismatch hostname of ssl session, sni: test.com, hostname: localhost



=== TEST 17: set verification (2 ssl objects, both have mTLS)
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
                uri = "/*"
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
                    skip_mtls_uri_regex = {
                        "/hello[0-9]+",
                    }
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



=== TEST 18: skip the mtls, although no client cert provided
--- exec
curl -k https://localhost:1994/hello1
--- response_body eval
qr/hello1 world/



=== TEST 19: skip the mtls, although with wrong client cert
--- exec
curl -k --cert t/certs/test2.crt --key t/certs/test2.key -k https://localhost:1994/hello1
--- response_body eval
qr/hello1 world/



=== TEST 20: mtls failed, returns 400
--- exec
curl -k https://localhost:1994/hello
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate was not present



=== TEST 21: mtls failed, wrong client cert
--- exec
curl --cert t/certs/test2.crt --key t/certs/test2.key -k https://localhost:1994/hello
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate verification is not passed: FAILED



=== TEST 22: mtls failed, at handshake phase
--- exec
curl -k -v --resolve "test.com:1994:127.0.0.1" https://test.com:1994/hello
--- error_log
peer did not return a certificate
