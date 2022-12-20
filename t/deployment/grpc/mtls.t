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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: mTLS for control plane
--- exec
grpcurl -import-path ./t/lib -proto etcd.proto -d '{}' -cert t/certs/mtls_client.crt -key t/certs/mtls_client.key -insecure localhost:12345 etcdserverpb.Maintenance.Status
--- response_body eval
qr/"version":/
--- yaml_config
deployment:
    role: control_plane
    role_control_plane:
        config_provider: etcd
        conf_server:
            listen: 0.0.0.0:12345
            cert: t/certs/mtls_server.crt
            cert_key: t/certs/mtls_server.key
            client_ca_cert: t/certs/mtls_ca.crt
    etcd:
        use_grpc: true
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
    certs:
        cert: t/certs/mtls_client.crt
        cert_key: t/certs/mtls_client.key
        trusted_ca_cert: t/certs/mtls_ca.crt



=== TEST 2: no client certificate
--- exec
curl -k https://localhost:12345/version
--- response_body eval
qr/No required SSL certificate was sent/
--- yaml_config
deployment:
    role: control_plane
    role_control_plane:
        config_provider: etcd
        conf_server:
            listen: 0.0.0.0:12345
            cert: t/certs/mtls_server.crt
            cert_key: t/certs/mtls_server.key
            client_ca_cert: t/certs/mtls_ca.crt
    etcd:
        use_grpc: true
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
    certs:
        cert: t/certs/mtls_client.crt
        cert_key: t/certs/mtls_client.key
        trusted_ca_cert: t/certs/mtls_ca.crt



=== TEST 3: wrong client certificate
--- exec
curl --cert t/certs/apisix.crt --key t/certs/apisix.key -k https://localhost:12345/version
--- response_body eval
qr/The SSL certificate error/
--- yaml_config
deployment:
    role: control_plane
    role_control_plane:
        config_provider: etcd
        conf_server:
            listen: 0.0.0.0:12345
            cert: t/certs/mtls_server.crt
            cert_key: t/certs/mtls_server.key
            client_ca_cert: t/certs/mtls_ca.crt
    etcd:
        use_grpc: true
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
    certs:
        cert: t/certs/mtls_client.crt
        cert_key: t/certs/mtls_client.key
        trusted_ca_cert: t/certs/mtls_ca.crt
