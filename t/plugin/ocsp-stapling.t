#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    # setup default conf.yaml
    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
plugins:
    - ocsp-stapling
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: disable ocsp-stapling plugin
--- extra_yaml_config
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/apisix.crt")
        local ssl_key =  t.read_file("t/certs/apisix.key")

        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "test.com",
            ocsp_stapling = true
        }

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
        )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        ngx.say(body)
    }
}
--- error_code: 400
--- error_log
additional properties forbidden, found ocsp_stapling



=== TEST 2: enable ocsp-stapling plugin, set cert which not support ocsp
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/apisix.crt")
        local ssl_key =  t.read_file("t/certs/apisix.key")

        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "test.com",
            ocsp_stapling = true
        }

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
        )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 3: no response send, get ocsp responder url failed:1
--- exec
openssl s_client -connect localhost:1994 -servername test.com -status
--- response_body_like eval
qr/CONNECTED/
--- error_log
ocsp response will not send, error info: failed to get ocsp url: nil



=== TEST 4: no response send, get ocsp responder url failed:2
--- exec
openssl s_client -connect localhost:1994 -servername test.com -status
--- response_body_like eval
qr/OCSP response: no response sent/
--- error_log
ocsp response will not send, error info: failed to get ocsp url: nil



=== TEST 5: enable ocsp-stapling plugin, set cert which support ocsp
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/ocsp/ocsp_rsa.crt")
        local ssl_key =  t.read_file("t/certs/ocsp/ocsp_rsa.key")

        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "ocsp.test.com",
            ocsp_stapling = true
        }

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
        )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 6: hit, get ocsp response:1
--- exec
openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/ca.crt -rkey t/certs/ocsp/ca.key -CA t/certs/ocsp/ca.crt -text -nrequest 1 -resp_no_certs &
openssl s_client -status -connect localhost:1994 -servername ocsp.test.com
--- response_body_like eval
qr/CONNECTED/



=== TEST 7: hit, get ocsp response:2
--- exec
openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/ca.crt -rkey t/certs/ocsp/ca.key -CA t/certs/ocsp/ca.crt -text -nrequest 1 -resp_no_certs &
openssl s_client -status -connect localhost:1994 -servername ocsp.test.com
--- response_body_like eval
qr/OCSP Response Status: successful/



=== TEST 8: enable ocsp-stapling plugin, set muilt cert which support ocsp
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local rsa_cert = t.read_file("t/certs/ocsp/ocsp_rsa.crt")
        local rsa_key =  t.read_file("t/certs/ocsp/ocsp_rsa.key")

        local ecc_cert = t.read_file("t/certs/ocsp/ocsp_ecc.crt")
        local ecc_key =  t.read_file("t/certs/ocsp/ocsp_ecc.key")

        local data = {
            cert = rsa_cert,
            key = rsa_key,
            certs = { ecc_cert },
            keys = { ecc_key },
            sni = "ocsp.test.com",
            ocsp_stapling = true
        }

        local code, body = t.test('/apisix/admin/ssls/1',
            ngx.HTTP_PUT,
            core.json.encode(data),
            [[{
                "value": {
                    "sni": "ocsp.test.com"
                },
                "key": "/apisix/ssls/1"
            }]]
        )
        ngx.status = code
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 9: hit rsa cert, get ocsp response:1
--- exec
openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/ca.crt -rkey t/certs/ocsp/ca.key -CA t/certs/ocsp/ca.crt -text -nrequest 1 -resp_no_certs &
openssl s_client -status -connect localhost:1994 -servername ocsp.test.com -tls1_2 -cipher 
--- response_body_like eval
qr/CONNECTED/



=== TEST 10: hit rsa cert, get ocsp response:2
--- exec
openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/ca.crt -rkey t/certs/ocsp/ca.key -CA t/certs/ocsp/ca.crt -text -nrequest 1 -resp_no_certs &
openssl s_client -status -connect localhost:1994 -servername ocsp.test.com -tls1_2 -cipher 
--- response_body_like eval
qr/OCSP Response Status: successful/



=== TEST 11: hit rsa cert, get ocsp response:3
--- exec
openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/ca.crt -rkey t/certs/ocsp/ca.key -CA t/certs/ocsp/ca.crt -text -nrequest 1 -resp_no_certs &
openssl s_client -status -connect localhost:1994 -servername ocsp.test.com -tls1_2 -cipher 
--- response_body_like eval
qr/OCSP Response Status: successful/



=== TEST 12: hit ecc cert, get ocsp response:1
--- exec
openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/ca.crt -rkey t/certs/ocsp/ca.key -CA t/certs/ocsp/ca.crt -text -nrequest 1 -resp_no_certs &
openssl s_client -status -connect localhost:1994 -servername ocsp.test.com -tls1_2 -cipher 
--- response_body_like eval
qr/CONNECTED/



=== TEST 13: hit ecc cert, get ocsp response:2
--- exec
openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/ca.crt -rkey t/certs/ocsp/ca.key -CA t/certs/ocsp/ca.crt -text -nrequest 1 -resp_no_certs &
openssl s_client -status -connect localhost:1994 -servername ocsp.test.com -tls1_2 -cipher 
--- response_body_like eval
qr/OCSP Response Status: successful/



=== TEST 14: hit rsa cert, get ocsp response:3
--- exec
openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/ca.crt -rkey t/certs/ocsp/ca.key -CA t/certs/ocsp/ca.crt -text -nrequest 1 -resp_no_certs &
openssl s_client -status -connect localhost:1994 -servername ocsp.test.com -tls1_2 -cipher 
--- response_body_like eval
qr/OCSP Response Status: successful/
