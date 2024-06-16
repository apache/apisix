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

=== TEST 1: enable mtls and ocsp-stapling plugin in route, but disable client cert ocsp verify
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_ca_cert = t.read_file("t/certs/apisix.crt")
            local ssl_cert = t.read_file("t/certs/mtls_server.crt")
            local ssl_key  = t.read_file("t/certs/mtls_server.key")
            local data = {
                plugins = {
                    ["ocsp-stapling"] = {},
                },
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
                sni = "admin.apisix.dev",
                client = {
                    ca = ssl_ca_cert,
                },
                ocsp_stapling = {
                    enabled = true,
                    ssl_ocsp = "off",
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



=== TEST 2: disable client cert ocsp verify, mtls passed when client cert is good status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_good.crt --key t/certs/ocsp/rsa_good.key 2>&1 | cat
--- response_body eval
qr/hello world/
--- error_log
no client cert ocsp verify required



=== TEST 3: disable client cert ocsp verify, mtls passed when client cert is good status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/ecc_good.crt --key t/certs/ocsp/ecc_good.key 2>&1 | cat
--- response_body eval
qr/hello world/
--- error_log
no client cert ocsp verify required



=== TEST 4: disable client cert ocsp verify, mtls passed when client cert is unknown status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_unknown.crt --key t/certs/ocsp/rsa_unknown.key 2>&1 | cat
--- response_body eval
qr/hello world/
--- error_log
no client cert ocsp verify required



=== TEST 5: disable client cert ocsp verify, mtls passed when client cert is revoked status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_revoked.crt --key t/certs/ocsp/rsa_revoked.key 2>&1 | cat
--- response_body eval
qr/hello world/
--- error_log
no client cert ocsp verify required



=== TEST 6: enable mtls and ocsp-stapling plugin in route, enable client cert ocsp verify
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_ca_cert = t.read_file("t/certs/apisix.crt")
            local ssl_cert = t.read_file("t/certs/mtls_server.crt")
            local ssl_key  = t.read_file("t/certs/mtls_server.key")
            local data = {
                plugins = {
                    ["ocsp-stapling"] = {},
                },
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
                sni = "admin.apisix.dev",
                client = {
                    ca = ssl_ca_cert,
                },
                ocsp_stapling = {
                    enabled = true,
                    ssl_ocsp = "leaf",
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



=== TEST 7: run ocsp responder, will exit when test finished
--- config
location /t {
    content_by_lua_block {
        local shell = require("resty.shell")
        local cmd = [[ /usr/local/openresty/openssl3/bin/openssl ocsp -index t/certs/ocsp/index.txt -port 11451 -rsigner t/certs/ocsp/signer.crt -rkey t/certs/ocsp/signer.key -CA t/certs/apisix.crt -nrequest 4 2>&1 1>/dev/null & ]]
        local ok, stdout, stderr, reason, status = shell.run(cmd, nil, 1000, 8096)
        if not ok then
            ngx.log(ngx.WARN, "failed to execute the script with status: " .. status or "nil" .. ", reason: " .. reason .. ", stderr: " .. stderr)
            return
        end
        ngx.print(stderr)
    }
}



=== TEST 8: enabled client cert ocsp verify, mtls passed when client cert is good status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_good.crt --key t/certs/ocsp/rsa_good.key 2>&1 | cat
--- response_body eval
qr/hello world/
--- error_log
validate client cert ocsp response ok



=== TEST 9: enabled client cert ocsp verify, mtls passed when client cert is good status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/ecc_good.crt --key t/certs/ocsp/ecc_good.key 2>&1 | cat
--- response_body eval
qr/hello world/
--- error_log
validate client cert ocsp response ok



=== TEST 10: enabled client cert ocsp verify, mtls failed when client cert is unknown status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_unknown.crt --key t/certs/ocsp/rsa_unknown.key 2>&1 | cat
--- response_body eval
qr/400 Bad Request/
--- error_log
failed to validate ocsp response: certificate status "unknown" in the OCSP response



=== TEST 11: enabled client cert ocsp verify, mtls failed when client cert is revoked status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_revoked.crt --key t/certs/ocsp/rsa_revoked.key 2>&1 | cat
--- response_body eval
qr/400 Bad Request/
--- error_log
failed to validate ocsp response: certificate status "revoked" in the OCSP response




=== TEST 7: run ocsp responder, will exit when test finished
--- config
location /t {
    content_by_lua_block {
        local shell = require("resty.shell")
        local cmd = [[ ps aux |grep openssl 1>&2 ]]
        local ok, stdout, stderr, reason, status = shell.run(cmd, nil, 1000, 8096)
        if not ok then
            ngx.log(ngx.WARN, "failed to execute the script with status: " .. status or "nil" .. ", reason: " .. reason .. ", stderr: " .. stderr)
            return
        end
        ngx.print(stderr)
    }
}
--- response_body
openssl


=== TEST 12: enable mtls and ocsp-stapling plugin in route, enable client cert ocsp verify but override ssl_ocsp_responder
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_ca_cert = t.read_file("t/certs/apisix.crt")
            local ssl_cert = t.read_file("t/certs/mtls_server.crt")
            local ssl_key  = t.read_file("t/certs/mtls_server.key")
            local data = {
                plugins = {
                    ["ocsp-stapling"] = {},
                },
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
                sni = "admin.apisix.dev",
                client = {
                    ca = ssl_ca_cert,
                },
                ocsp_stapling = {
                    enabled = true,
                    ssl_ocsp = "leaf",
                    ssl_ocsp_responder = "http://127.0.0.1:12345/",
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



=== TEST 13: run ocsp responder, will exit when test finished
--- config
location /t {
    content_by_lua_block {
        local shell = require("resty.shell")
        local cmd = [[ /usr/local/openresty/openssl3/bin/openssl ocsp -index t/certs/ocsp/index.txt -port 12345 -rsigner t/certs/ocsp/signer.crt -rkey t/certs/ocsp/signer.key -CA t/certs/apisix.crt -nrequest 4 2>&1 1>/dev/null & ]]
        local ok, stdout, stderr, reason, status = shell.run(cmd, nil, 1000, 8096)
        if not ok then
            ngx.log(ngx.WARN, "failed to execute the script with status: " .. status or "nil" .. ", reason: " .. reason .. ", stderr: " .. stderr)
            return
        end
        ngx.print(stderr)
    }
}



=== TEST 14: enabled client cert ocsp verify, mtls passed when client cert is good status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_good.crt --key t/certs/ocsp/rsa_good.key 2>&1 | cat
--- response_body eval
qr/hello world/
--- error_log
validate client cert ocsp response ok



=== TEST 15: enabled client cert ocsp verify, mtls passed when client cert is good status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/ecc_good.crt --key t/certs/ocsp/ecc_good.key 2>&1 | cat
--- response_body eval
qr/hello world/
--- error_log
validate client cert ocsp response ok



=== TEST 16: enabled client cert ocsp verify, mtls failed when client cert is unknown status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_unknown.crt --key t/certs/ocsp/rsa_unknown.key 2>&1 | cat
--- response_body eval
qr/400 Bad Request/
--- error_log
failed to validate ocsp response: certificate status "unknown" in the OCSP response



=== TEST 17: enabled client cert ocsp verify, mtls failed when client cert is revoked status
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_revoked.crt --key t/certs/ocsp/rsa_revoked.key 2>&1 | cat
--- response_body eval
qr/400 Bad Request/
--- error_log
failed to validate ocsp response: certificate status "revoked" in the OCSP response



=== TEST 18: enabled client cert ocsp verify, mtls failed because override responder is closed
--- exec
curl -i -v https://admin.apisix.dev:1994/hello --cacert t/certs/mtls_ca.crt --cert t/certs/ocsp/rsa_good.crt --key t/certs/ocsp/rsa_good.key 2>&1 | cat
--- response_body eval
qr/400 Bad Request/
--- error_log
failed to get ocsp respone: ocsp responder query failed: connection refused
