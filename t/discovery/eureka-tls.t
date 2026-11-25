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
use Cwd qw(abs_path);
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

my $certs = abs_path("t/certs");
our $tls_servers = <<_EOC_;
    lua_ssl_trusted_certificate cert/apisix.crt;
    server {
        listen 21981 ssl;
        listen 21983;
        ssl_certificate $certs/localhost_slapd_cert.pem;
        ssl_certificate_key $certs/localhost_slapd_key.pem;
        location / {
            content_by_lua_block {
                local instance = {app = "SAMPLE", status = "UP", ipAddr = "127.0.0.1",
                                  port = {["\@enabled"] = "true", ["\$"] = 8080},
                                  securePort = {["\@enabled"] = "false", ["\$"] = 443}}
                local app = {name = "SAMPLE", instance = {instance}}
                ngx.say(require("cjson").encode({applications = {application = {app}}}))
            }
        }
    }
    server {
        listen 21982 ssl;
        ssl_certificate cert/apisix.crt;
        ssl_certificate_key cert/apisix.key;
        location / { return 200; }
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: accept the trusted receiver identity
--- http_config eval: $::tls_servers
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  eureka:
    host: ["https://localhost:21981"]
    fetch_interval: 1
--- apisix_yaml
routes: []
#END
--- config
    location = /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.eureka")
            for i = 1, 50 do
                local nodes = discovery.dump_data().services.SAMPLE
                if nodes then
                    ngx.say(nodes[1].port)
                    return
                end
                ngx.sleep(0.05)
            end
            ngx.say("registry was not loaded")
        }
    }
--- request
GET /t
--- response_body
8080
--- no_error_log
failed to fetch registry



=== TEST 2: reject a certificate for another host
--- http_config eval: $::tls_servers
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  eureka:
    host: ["https://localhost:21982"]
    fetch_interval: 1
--- apisix_yaml
routes: []
#END
--- config
    location = /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.eureka")
            local nodes = discovery.dump_data().services.SAMPLE
            ngx.say(nodes and nodes[1].port or "no nodes")
        }
    }
--- request
GET /t
--- wait: 0.5
--- response_body
no nodes
--- error_log
certificate host mismatch



=== TEST 3: skip certificate verification when ssl_verify is false
--- http_config eval: $::tls_servers
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  eureka:
    host: ["https://127.0.0.1:21981"]
    fetch_interval: 1
    ssl_verify: false
--- apisix_yaml
routes: []
#END
--- config
    location = /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.eureka")
            for i = 1, 50 do
                local nodes = discovery.dump_data().services.SAMPLE
                if nodes then
                    ngx.say(nodes[1].port)
                    return
                end
                ngx.sleep(0.05)
            end
            ngx.say("registry was not loaded")
        }
    }
--- request
GET /t
--- response_body
8080
--- no_error_log
failed to fetch registry



=== TEST 4: ssl_verify does not affect an http registry
--- http_config eval: $::tls_servers
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  eureka:
    host: ["http://127.0.0.1:21983"]
    fetch_interval: 1
    ssl_verify: true
--- apisix_yaml
routes: []
#END
--- config
    location = /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.eureka")
            for i = 1, 50 do
                local nodes = discovery.dump_data().services.SAMPLE
                if nodes then
                    ngx.say(nodes[1].port)
                    return
                end
                ngx.sleep(0.05)
            end
            ngx.say("registry was not loaded")
        }
    }
--- request
GET /t
--- response_body
8080
--- no_error_log
failed to fetch registry
