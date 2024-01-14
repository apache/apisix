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

my $openssl_bin = $ENV{OPENSSL_BIN};
if (! -x $openssl_bin) {
    $ENV{OPENSSL_BIN} = '/usr/local/openresty/openssl3/bin/openssl';
    if (! -x $ENV{OPENSSL_BIN}) {
        plan(skip_all => "openssl3 not installed");
    }
}

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
            ocsp_stapling = {}
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



=== TEST 2: check schema when enabled ocsp-stapling plugin
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local json = require("toolkit.json")

        for _, conf in ipairs({
            {},
            {enabled = true},
            {skip_verify = true},
            {cache_ttl = 6000},
            {enabled = true, skip_verify = true, cache_ttl = 6000},
        }) do
            local ok, err = core.schema.check(core.schema.ssl.properties.ocsp_stapling, conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(json.encode(conf))
        end
    }
}
--- response_body
{"cache_ttl":3600,"enabled":false,"skip_verify":false}
{"cache_ttl":3600,"enabled":true,"skip_verify":false}
{"cache_ttl":3600,"enabled":false,"skip_verify":true}
{"cache_ttl":6000,"enabled":false,"skip_verify":false}
{"cache_ttl":6000,"enabled":true,"skip_verify":true}



=== TEST 3: ssl config without "ocsp-stapling" field when enabled ocsp-stapling plugin
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



=== TEST 4: hit, handshake ok:1
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername test.com -status 2>&1 | cat
--- response_body eval
qr/CONNECTED/
--- error_log
no 'ocsp_stapling' field found, no need to run ocsp-stapling plugin



=== TEST 5: hit, no ocsp response send:2
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername test.com -status 2>&1 | cat
--- response_body eval
qr/OCSP response: no response sent/
--- error_log
no 'ocsp_stapling' field found, no need to run ocsp-stapling plugin



=== TEST 6: client hello without status request extension required when enabled ocsp-stapling plugin
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/ocsp/rsa_good.crt")
        local ssl_key =  t.read_file("t/certs/ocsp/rsa_good.key")

        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "ocsp.test.com",
            ocsp_stapling = {
                enabled = true
            }
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



=== TEST 7: hit, handshake ok and no ocsp response send
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername ocsp.test.com 2>&1 | cat
--- response_body eval
qr/CONNECTED/
--- error_log
no status request required, no need to send ocsp response



=== TEST 8: cert without ocsp supported when enabled ocsp-stapling plugin
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
            ocsp_stapling = {
                enabled = true
            }
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



=== TEST 9: hit, handshake ok:1
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername test.com -status 2>&1 | cat
--- response_body eval
qr/CONNECTED/
--- error_log
no ocsp response send: failed to get ocsp url: cert not contains authority_information_access extension



=== TEST 10: hit, no ocsp response send due to get ocsp responder url failed:2
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername test.com -status 2>&1 | cat
--- response_body eval
qr/OCSP response: no response sent/
--- error_log
no ocsp response send: failed to get ocsp url: cert not contains authority_information_access extension



=== TEST 11: run ocsp responseder, will exit when test finished
--- config
location /t {
    content_by_lua_block {
        local shell = require("resty.shell")
        local cmd = [[ openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/signer.crt -rkey t/certs/ocsp/signer.key -CA t/certs/apisix.crt -nrequest 16 2>&1 1>/dev/null & ]]
        local ok, stdout, stderr, reason, status = shell.run(cmd, nil, 1000, 8096)
        if not ok then
            ngx.log(ngx.WARN, "failed to execute the script with status: " .. status .. ", reason: " .. reason .. ", stderr: " .. stderr)
            return
        end
        ngx.print(stderr)
    }
}



=== TEST 12: cert with ocsp supported when enabled ocsp-stapling plugin
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/ocsp/rsa_good.crt")
        local ssl_key =  t.read_file("t/certs/ocsp/rsa_good.key")

        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "ocsp.test.com",
            ocsp_stapling = {
                enabled = true
            }
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



=== TEST 13: hit, handshake ok:1
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp.test.com 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/CONNECTED/



=== TEST 14: hit, get ocsp response and status is good:2
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp.test.com 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/Cert Status: good/



=== TEST 15: muilt cert with ocsp supported when enabled ocsp-stapling plugin
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local rsa_cert = t.read_file("t/certs/ocsp/rsa_good.crt")
        local rsa_key =  t.read_file("t/certs/ocsp/rsa_good.key")

        local ecc_cert = t.read_file("t/certs/ocsp/ecc_good.crt")
        local ecc_key =  t.read_file("t/certs/ocsp/ecc_good.key")

        local data = {
            cert = rsa_cert,
            key = rsa_key,
            certs = { ecc_cert },
            keys = { ecc_key },
            sni = "ocsp.test.com",
            ocsp_stapling = {
                enabled = true
            }
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



=== TEST 16: hit ecc cert, handshake ok:1
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername ocsp.test.com -status -tls1_2 -cipher ECDHE-ECDSA-AES128-GCM-SHA256 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/CONNECTED/



=== TEST 17: hit ecc cert, get cert signature type:2
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername ocsp.test.com -status -tls1_2 -cipher ECDHE-ECDSA-AES128-GCM-SHA256 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/Peer signature type: ECDSA/



=== TEST 18: hit ecc cert, get ocsp response and status is good:3
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername ocsp.test.com -status -tls1_2 -cipher ECDHE-ECDSA-AES128-GCM-SHA256 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/Cert Status: good/



=== TEST 19: hit rsa cert, handshake ok:1
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername ocsp.test.com -status -tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/CONNECTED/



=== TEST 20: hit rsa cert, get cert signature type:2
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername ocsp.test.com -status -tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/Peer signature type: RSA/



=== TEST 21: hit rsa cert, get ocsp response and status is good:3
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -connect localhost:1994 -servername ocsp.test.com -status -tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/Cert Status: good/



=== TEST 22: cert with ocsp supported and revoked when enabled ocsp-stapling plugin
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/ocsp/rsa_revoked.crt")
        local ssl_key =  t.read_file("t/certs/ocsp/rsa_revoked.key")
    
        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "ocsp-revoked.test.com",
            ocsp_stapling = {
                enabled = true
            }
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



=== TEST 23: hit revoked rsa cert, handshake ok:1
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp-revoked.test.com 2>&1 | cat
--- response_body eval
qr/CONNECTED/
--- error_log
no ocsp response send: failed to validate ocsp response: certificate status "revoked" in the OCSP response



=== TEST 24: hit revoked rsa cert, no ocsp response send:2
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp-revoked.test.com 2>&1 | cat
--- response_body eval
qr/OCSP response: no response sent/
--- error_log
no ocsp response send: failed to validate ocsp response: certificate status "revoked" in the OCSP response



=== TEST 25: cert with ocsp supported and revoked when enabled ocsp-stapling plugin, and skip verify
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/ocsp/rsa_revoked.crt")
        local ssl_key =  t.read_file("t/certs/ocsp/rsa_revoked.key")
    
        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "ocsp-revoked.test.com",
            ocsp_stapling = {
                enabled = true,
                skip_verify = true,
            }
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



=== TEST 26: hit revoked rsa cert, handshake ok:1
--- max_size: 16096
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp-revoked.test.com 2>&1 | cat
--- response_body eval
qr/CONNECTED/



=== TEST 27: hit revoked rsa cert, get ocsp response and status is revoked:2
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp-revoked.test.com 2>&1 | cat
--- max_size: 16096
--- response_body eval
qr/Cert Status: revoked/



=== TEST 28: cert with ocsp supported and unknown status when enabled ocsp-stapling plugin
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/ocsp/rsa_unknown.crt")
        local ssl_key =  t.read_file("t/certs/ocsp/rsa_unknown.key")
    
        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "ocsp-unknown.test.com",
            ocsp_stapling = {
                enabled = true
            }
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



=== TEST 29: hit unknown rsa cert, handshake ok:1
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp-unknown.test.com 2>&1 | cat
--- response_body eval
qr/CONNECTED/
--- error_log
no ocsp response send: failed to validate ocsp response: certificate status "unknown" in the OCSP response



=== TEST 30: hit unknown rsa cert, no ocsp response send:2
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp-unknown.test.com 2>&1 | cat
--- response_body eval
qr/OCSP response: no response sent/
--- error_log
no ocsp response send: failed to validate ocsp response: certificate status "unknown" in the OCSP response



=== TEST 31: cert with ocsp supported and unknown status when enabled ocsp-stapling plugin, and skip verify
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/ocsp/rsa_unknown.crt")
        local ssl_key =  t.read_file("t/certs/ocsp/rsa_unknown.key")
    
        local data = {
            cert = ssl_cert,
            key = ssl_key,
            sni = "ocsp-unknown.test.com",
            ocsp_stapling = {
                enabled = true,
                skip_verify = true,
            }
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



=== TEST 32: hit unknown rsa cert, handshake ok:1
--- max_size: 16096
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp-unknown.test.com 2>&1 | cat
--- response_body eval
qr/CONNECTED/



=== TEST 33: hit unknown rsa cert, get ocsp response and status is unknown:2
--- max_size: 16096
--- exec
echo -n "Q" | $OPENSSL_BIN s_client -status -connect localhost:1994 -servername ocsp-unknown.test.com 2>&1 | cat
--- response_body eval
qr/Cert Status: unknown/
