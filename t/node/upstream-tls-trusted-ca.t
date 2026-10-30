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
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    # nginx.conf renders proxy_ssl_trusted_certificate and
    # grpc_ssl_trusted_certificate from apisix.ssl.ssl_trusted_certificate,
    # but proxy_ssl_verify and grpc_ssl_verify stay off
    my $static_verify = "";
    if ($block->static_verify) {
        $static_verify = <<_EOC_;
proxy_ssl_verify on;
grpc_ssl_verify on;
_EOC_
    }

    # the CRL only covers crl_ca.crt, so the chain_root.crt cases go without it
    my $trusted = <<_EOC_;
proxy_ssl_trusted_certificate ../../certs/crl_ca.crt;
grpc_ssl_trusted_certificate ../../certs/crl_ca.crt;
proxy_ssl_crl ../../certs/crl_ca.crl;
grpc_ssl_crl ../../certs/crl_ca.crl;
_EOC_
    if ($block->chain) {
        $trusted = <<_EOC_;
proxy_ssl_trusted_certificate ../../certs/chain_root.crt;
grpc_ssl_trusted_certificate ../../certs/chain_root.crt;
_EOC_
    }

    my $http_config = <<_EOC_;
$trusted
$static_verify

server {
    listen 8770 ssl;
    http2 on;
    ssl_certificate ../../certs/crl_server.crt;
    ssl_certificate_key ../../certs/crl_server.key;

    location / {
        return 200 'ok\\n';
    }
}

server {
    listen 8771 ssl;
    http2 on;
    ssl_certificate ../../certs/crl_revoked.crt;
    ssl_certificate_key ../../certs/crl_revoked.key;

    location / {
        return 200 'ok\\n';
    }
}

server {
    listen 8772 ssl;
    http2 on;
    ssl_certificate ../../certs/mtls_server.crt;
    ssl_certificate_key ../../certs/mtls_server.key;

    location / {
        return 200 'ok\\n';
    }
}

server {
    listen 8773 ssl;
    http2 on;
    # leaf and two intermediates
    ssl_certificate ../../certs/chain_server.crt;
    ssl_certificate_key ../../certs/chain_server.key;

    location / {
        return 200 'ok\\n';
    }
}
_EOC_

    $block->set_value("http_config", $http_config);

    my $routes = "routes:\n";
    my %ports = (good => 8770, revoked => 8771, untrusted => 8772, chain => 8773);
    my $id = 0;
    for my $scheme ("https", "grpcs") {
        for my $name (sort keys %ports) {
            for my $verify ("verify", "noverify", "default") {
                $id++;
                my $tls = "";
                if ($verify ne "default") {
                    my $on = $verify eq "verify" ? "true" : "false";
                    $tls = "      tls:\n        verify: $on\n";
                }
                $routes .= <<_EOC_;
  - id: $id
    uri: /$scheme/$verify/$name
    upstream:
      scheme: $scheme
      type: roundrobin
      pass_host: rewrite
      upstream_host: admin.apisix.dev
      nodes:
        "127.0.0.1:$ports{$name}": 1
$tls
_EOC_
            }
        }
    }
    $routes .= "#END\n";

    $block->set_value("apisix_yaml", $routes);

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: https, tls.verify, certificate signed by a trusted CA
--- request
GET /https/verify/good
--- response_body
ok



=== TEST 2: https, tls.verify, revoked certificate
--- request
GET /https/verify/revoked
--- error_code: 502
--- error_log
upstream SSL certificate verify error: (23:certificate revoked)



=== TEST 3: https, tls.verify, certificate signed by an untrusted CA
--- request
GET /https/verify/untrusted
--- error_code: 502
--- error_log eval
qr/upstream SSL certificate verify error: \(2[01]:unable to (get local issuer certificate|verify the first certificate)\)/



=== TEST 4: https, tls.verify unset, no verification
--- pipelined_requests eval
["GET /https/default/good", "GET /https/default/revoked", "GET /https/default/untrusted"]
--- response_body eval
["ok\n", "ok\n", "ok\n"]



=== TEST 5: https, static verify, tls.verify, certificate signed by a trusted CA
--- static_verify: true
--- request
GET /https/verify/good
--- response_body
ok



=== TEST 6: https, static verify, tls.verify, revoked certificate
--- static_verify: true
--- request
GET /https/verify/revoked
--- error_code: 502
--- error_log
upstream SSL certificate verify error: (23:certificate revoked)



=== TEST 7: https, static verify, tls.verify unset, revoked certificate
--- static_verify: true
--- request
GET /https/default/revoked
--- error_code: 502
--- error_log
upstream SSL certificate verify error: (23:certificate revoked)



=== TEST 8: grpcs, tls.verify, certificate signed by a trusted CA
--- request
GET /grpcs/verify/good
--- response_body
ok



=== TEST 9: grpcs, tls.verify, revoked certificate
--- request
GET /grpcs/verify/revoked
--- error_code: 502
--- error_log
upstream SSL certificate verify error: (23:certificate revoked)



=== TEST 10: grpcs, tls.verify, certificate signed by an untrusted CA
--- request
GET /grpcs/verify/untrusted
--- error_code: 502
--- error_log eval
qr/upstream SSL certificate verify error: \(2[01]:unable to (get local issuer certificate|verify the first certificate)\)/



=== TEST 11: grpcs, tls.verify unset, no verification
--- pipelined_requests eval
["GET /grpcs/default/good", "GET /grpcs/default/revoked", "GET /grpcs/default/untrusted"]
--- response_body eval
["ok\n", "ok\n", "ok\n"]



=== TEST 12: grpcs, static verify, tls.verify, certificate signed by a trusted CA
--- static_verify: true
--- request
GET /grpcs/verify/good
--- response_body
ok



=== TEST 13: grpcs, static verify, tls.verify, revoked certificate
--- static_verify: true
--- request
GET /grpcs/verify/revoked
--- error_code: 502
--- error_log
upstream SSL certificate verify error: (23:certificate revoked)



=== TEST 14: https, tls.verify false, no verification
--- request
GET /https/noverify/untrusted
--- response_body
ok



=== TEST 15: https, static verify, tls.verify false, no verification
--- static_verify: true
--- request
GET /https/noverify/untrusted
--- response_body
ok



=== TEST 16: https, tls.verify, two intermediates, no depth limit
--- chain: true
--- request
GET /https/verify/chain
--- response_body
ok



=== TEST 17: https, static verify, tls.verify, default verify depth
--- static_verify: true
--- chain: true
--- request
GET /https/verify/chain
--- error_code: 502
--- error_log eval
qr/upstream SSL certificate verify error: \((20:unable to get local issuer certificate|22:certificate chain too long)\)/



=== TEST 18: https, static verify, tls.verify unset, default verify depth
--- static_verify: true
--- chain: true
--- request
GET /https/default/chain
--- error_code: 502
--- error_log eval
qr/upstream SSL certificate verify error: \((20:unable to get local issuer certificate|22:certificate chain too long)\)/



=== TEST 19: grpcs, tls.verify false, no verification
--- request
GET /grpcs/noverify/untrusted
--- response_body
ok



=== TEST 20: grpcs, static verify, tls.verify false, no verification
--- static_verify: true
--- request
GET /grpcs/noverify/untrusted
--- response_body
ok



=== TEST 21: grpcs, static verify, tls.verify unset, revoked certificate
--- static_verify: true
--- request
GET /grpcs/default/revoked
--- error_code: 502
--- error_log
upstream SSL certificate verify error: (23:certificate revoked)



=== TEST 22: grpcs, tls.verify, two intermediates, no depth limit
--- chain: true
--- request
GET /grpcs/verify/chain
--- response_body
ok



=== TEST 23: grpcs, static verify, tls.verify, default verify depth
--- static_verify: true
--- chain: true
--- request
GET /grpcs/verify/chain
--- error_code: 502
--- error_log eval
qr/upstream SSL certificate verify error: \((20:unable to get local issuer certificate|22:certificate chain too long)\)/



=== TEST 24: grpcs, static verify, tls.verify unset, default verify depth
--- static_verify: true
--- chain: true
--- request
GET /grpcs/default/chain
--- error_code: 502
--- error_log eval
qr/upstream SSL certificate verify error: \((20:unable to get local issuer certificate|22:certificate chain too long)\)/
