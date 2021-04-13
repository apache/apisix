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
            local code, body = t.test('/apisix/admin/ssl/1',
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
            local code, body = t.test('/apisix/admin/ssl/1',
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
            local code, body = t.test('/apisix/admin/ssl/1',
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
--- error_code: 400
--- error_log
client certificate was not present



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
--- error_code: 400
--- error_log
clent certificate verification is not passed: FAILED:self signed certificate
