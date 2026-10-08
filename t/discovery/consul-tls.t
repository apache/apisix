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
use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();


add_block_preprocessor(sub {
    my ($block) = @_;

    # a TLS endpoint fronting the consul agent on 8500, its certificate
    # (localhost) is signed by apisix.crt; the trust store is the http level
    # lua_ssl_trusted_certificate, as apisix.ssl.ssl_trusted_certificate renders it
    my $http_config = $block->http_config // <<_EOC_;
    lua_ssl_trusted_certificate ../../certs/apisix.crt;

    server {
        listen 18501 ssl;
        ssl_certificate             ../../certs/localhost_slapd_cert.pem;
        ssl_certificate_key         ../../certs/localhost_slapd_key.pem;

        location / {
            proxy_pass http://127.0.0.1:8500;
            proxy_read_timeout 70s;
        }
    }

    server {
        listen 30511;

        location /hello {
            content_by_lua_block {
                ngx.say("server 1")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});


sub main::yaml_config {
    my ($servers, $keepalive) = @_;
    return <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "$servers"
    timeout:
      connect: 1000
      read: 1000
      wait: 60
    weight: 1
    fetch_interval: 1
    keepalive: $keepalive
_EOC_
}

our $apisix_yaml = <<_EOC_;
routes:
  -
    uri: /hello
    upstream:
      service_name: service_tls
      discovery_type: consul
      type: roundrobin
#END
_EOC_


run_tests();

__DATA__

=== TEST 1: prepare consul catalog register nodes
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
--- request eval
"PUT /v1/agent/service/register\n" . "{\"ID\":\"service_tls1\",\"Name\":\"service_tls\",\"Address\":\"127.0.0.1\",\"Port\":30511}"
--- error_code: 200



=== TEST 2: https consul server (long connect type)
--- yaml_config eval: main::yaml_config("https://localhost:18501", "true")
--- apisix_yaml eval: $::apisix_yaml
--- request
GET /hello
--- response_body
server 1
--- no_error_log
[error]



=== TEST 3: https consul server (short connect type)
--- yaml_config eval: main::yaml_config("https://localhost:18501", "false")
--- apisix_yaml eval: $::apisix_yaml
--- request
GET /hello
--- response_body
server 1
--- no_error_log
[error]



=== TEST 4: scheme per server address, other schemes are still rejected
--- config
    location /t {
        content_by_lua_block {
            local client = require("apisix.discovery.consul.client")
            local timeout = {connect = 1000, read = 1000, wait = 60}

            local servers, err = client.format_consul_params({
                servers = {"http://127.0.0.1:8500", "https://consul.local"},
                timeout = timeout,
            })
            for _, s in ipairs(servers or {}) do
                ngx.say(s.host, ":", s.port, " ssl: ", s.ssl)
            end

            servers, err = client.format_consul_params({
                servers = {"https://127.0.0.1:8501", "tcp://127.0.0.1:8500"},
                timeout = timeout,
            })
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
127.0.0.1:8500 ssl: false
consul.local:443 ssl: true
only support consul http or https schema address, eg: http://address:port or https://address:port



=== TEST 5: clean nodes
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
--- request
PUT /v1/agent/service/deregister/service_tls1
--- error_code: 200
