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

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

my $openssl_bin = $ENV{OPENSSL_BIN};
if (! -x $openssl_bin) {
    $ENV{OPENSSL_BIN} = '/usr/local/openresty/openssl3/bin/openssl';
    if (! -x $ENV{OPENSSL_BIN}) {
        plan(skip_all => "openssl3 not installed");
    }
}

plan('no_plan');

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - 9100
  enable_resolv_search_opt: false
  ssl:
    ssl_protocols: TLSv1.1 TLSv1.2 TLSv1.3
    ssl_ciphers: ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES256-SHA:DHE-DSS-AES256-SHA
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests();

__DATA__

=== TEST 1: set route
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "upstream": {
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin"
                },
                "uris": ["/hello", "/world"]
            }]]
        )
        if code >= 300 then
            ngx.status = code
            ngx.say(message)
            return
        end
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed



=== TEST 2:  create ssl for test.com (unset ssl_protocols)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com",
                        "ssl_protocols": null,
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



=== TEST 3: Successfully, access test.com with TLSv1.3
--- exec
echo -n "Q"  | $OPENSSL_BIN s_client -connect 127.0.0.1:1994 -servername test.com -tls1_3 2>&1 | cat
--- response_body eval
qr/Server certificate/



=== TEST 4: Successfully, access test.com with TLSv1.2
--- exec
curl -k -v --tls-max 1.2 --tlsv1.2 --resolve "test.com:1994:127.0.0.1" https://test.com:1994/hello 2>&1 | cat
--- response_body eval
qr/TLSv1\.2 \(IN\), TLS handshake, Server hello(?s).*hello world/



=== TEST 5: Successfully, access test.com with TLSv1.1
--- exec
echo -n "Q"  | $OPENSSL_BIN s_client -connect 127.0.0.1:1994 -servername test.com -tls1_1 2>&1 | cat
--- response_body eval
qr/Server certificate/



=== TEST 6: set TLSv1.2 and TLSv1.3 for test.com
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com", ssl_protocols = {"TLSv1.2", "TLSv1.3"}}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com",
                        "ssl_protocols": ["TLSv1.2", "TLSv1.3"],
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



=== TEST 7: Set TLSv1.3 for the test2.com
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/test2.crt")
        local ssl_key =  t.read_file("t/certs/test2.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "test2.com", ssl_protocols = {"TLSv1.3"}}

        local code, body = t.test('/apisix/admin/ssls/2',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "test2.com"
                },
                "key": "/apisix/ssls/2"
            }]]
        )

        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed
--- request
GET /t



=== TEST 8: Successfully, access test.com with TLSv1.3
--- exec
echo -n "Q"  | $OPENSSL_BIN s_client -connect 127.0.0.1:1994 -servername test.com -tls1_3 2>&1 | cat
--- response_body eval
qr/Server certificate/



=== TEST 9: Successfully, access test.com with TLSv1.2
--- exec
curl -k -v --tls-max 1.2 --tlsv1.2 --resolve "test.com:1994:127.0.0.1" https://test.com:1994/hello 2>&1 | cat
--- response_body eval
qr/TLSv1\.2 \(IN\), TLS handshake, Server hello(?s).*hello world/



=== TEST 10: Successfully, access test2.com with TLSv1.3
--- exec
echo -n "Q"  | $OPENSSL_BIN s_client -connect 127.0.0.1:1994 -servername test2.com -tls1_3 2>&1 | cat
--- response_body eval
qr/Server certificate/



=== TEST 11: Failed, access test2.com with TLSv1.2
--- exec
curl -k -v --tls-max 1.2 --tlsv1.2 --resolve "test2.com:1994:127.0.0.1" https://test2.com:1994/hello 2>&1 | cat
--- response_body eval
qr/TLSv1\.2 \(IN\), TLS alert/



=== TEST 12: set TLSv1.1 for test.com
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com", ssl_protocols = {"TLSv1.1"}}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com",
                        "ssl_protocols": ["TLSv1.1"],
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



=== TEST 13: Successfully, access test.com with TLSv1.1
--- exec
echo -n "Q"  | $OPENSSL_BIN s_client -connect 127.0.0.1:1994 -servername test.com -tls1_1 2>&1 | cat
--- response_body eval
qr/Server certificate/



=== TEST 14: Failed, access test.com with TLSv1.3
--- exec
echo -n "Q"  | $OPENSSL_BIN s_client -connect 127.0.0.1:1994 -servername test.com -tls1_3 2>&1 | cat
--- response_body eval
qr/tlsv1 alert/
