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

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: set client certificate
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
                        ["127.0.0.1:2005"] = 1,
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
                        ["127.0.0.1:1995"] = 1,
                    },
                }
            }
            assert(t.test('/apisix/admin/stream_routes/1',
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



=== TEST 2: hit
--- stream_enable
--- request
GET /mtls
--- more_headers
Host: localhost
--- ignore_response
--- error_log
proxy request to 127.0.0.1:2005
proxy request to 127.0.0.1:1995



=== TEST 3: reject client without cetificate
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
                        ["127.0.0.1:2005"] = 1,
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
            ngx.print(body)
        }
    }
--- request
GET /t



=== TEST 4: hit
--- stream_enable
--- request
GET /mtls
--- more_headers
Host: localhost
--- ignore_response
--- error_log
proxy request to 127.0.0.1:2005
--- no_error_log
proxy request to 127.0.0.1:1995



=== TEST 5: reject client with bad cetificate
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
                        ["127.0.0.1:2005"] = 1,
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
            ngx.print(body)
        }
    }
--- request
GET /t



=== TEST 6: hit
--- stream_enable
--- request
GET /mtls
--- more_headers
Host: localhost
--- ignore_response
--- error_log
proxy request to 127.0.0.1:2005
--- no_error_log
proxy request to 127.0.0.1:1995
