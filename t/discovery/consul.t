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

    my $http_config = $block->http_config // <<_EOC_;
    map \${http_host} \${backend} {
      default service_a;
    }

    server {
        listen 20999;

        location / {
            content_by_lua_block {
                ngx.say("missing consul services")
            }
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
    server {
        listen 30512;

        location /hello {
            content_by_lua_block {
                ngx.say("server 2")
            }
        }
    }
    server {
        listen 30513;

        location /hello {
            content_by_lua_block {
                ngx.say("server 3")
            }
        }
    }
    server {
        listen 30514;

        location /hello {
            content_by_lua_block {
                ngx.say("server 4")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  enable_control: true
  control:
    ip: 127.0.0.1
    port: 9090
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
    skip_services:
      - "service_c"
    timeout:
      connect: 1000
      read: 1000
      wait: 60
    weight: 1
    fetch_interval: 1
    keepalive: true
    default_service:
      host: "127.0.0.1"
      port: 20999
      metadata:
        fail_timeout: 1
        weight: 1
        max_fails: 1
_EOC_

our $yaml_config_with_acl = <<_EOC_;
apisix:
  node_listen: 1984
  enable_control: true
  control:
    ip: 127.0.0.1
    port: 9090
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8502"
    token: "2b778dd9-f5f1-6f29-b4b4-9a5fa948757a"
    skip_services:
      - "service_c"
    timeout:
      connect: 1000
      read: 1000
      wait: 60
    weight: 1
    fetch_interval: 1
    keepalive: true
    default_service:
      host: "127.0.0.1"
      port: 20999
      metadata:
        fail_timeout: 1
        weight: 1
        max_fails: 1
_EOC_


run_tests();

__DATA__

=== TEST 1: prepare consul catalog register nodes
--- config
location /consul1 {
    rewrite  ^/consul1/(.*) /v1/agent/service/$1 break;
    proxy_pass http://127.0.0.1:8500;
}

location /consul2 {
    rewrite  ^/consul2/(.*) /v1/agent/service/$1 break;
    proxy_pass http://127.0.0.1:8600;
}
--- pipelined_requests eval
[
    "PUT /consul1/deregister/service_a1",
    "PUT /consul1/deregister/service_b1",
    "PUT /consul1/deregister/service_a2",
    "PUT /consul1/deregister/service_b2",
    "PUT /consul2/deregister/service_a1",
    "PUT /consul2/deregister/service_b1",
    "PUT /consul2/deregister/service_a2",
    "PUT /consul2/deregister/service_b2",
    "PUT /consul1/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul1/register\n" . "{\"ID\":\"service_a2\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30512,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul1/register\n" . "{\"ID\":\"service_b1\",\"Name\":\"service_b\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30513,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul1/register\n" . "{\"ID\":\"service_b2\",\"Name\":\"service_b\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30514,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
]
--- error_code eval
[200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200]



=== TEST 2: test consul server 1
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service_a
      discovery_type: consul
      type: roundrobin
#END
--- pipelined_requests eval
[
    "GET /hello",
    "GET /hello",
]
--- response_body_like eval
[
    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
]
--- no_error_log
[error, error]



=== TEST 3: test consul server 2
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service_b
      discovery_type: consul
      type: roundrobin
#END
--- pipelined_requests eval
[
    "GET /hello",
    "GET /hello"
]
--- response_body_like eval
[
    qr/server [3-4]\n/,
    qr/server [3-4]\n/,
]
--- no_error_log
[error, error]



=== TEST 4: test mini consul config
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:6500"
#END
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: service_a
      discovery_type: consul
      type: roundrobin
#END
--- request
GET /hello
--- response_body_like eval
qr/server [1-2]/
--- ignore_error_log



=== TEST 5: test invalid service name sometimes the consul key maybe deleted by mistake

--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service_c
      discovery_type: consul
      type: roundrobin
#END
--- pipelined_requests eval
[
    "GET /hello_api",
    "GET /hello_api"
]
--- response_body eval
[
    "missing consul services\n",
    "missing consul services\n"
]
--- ignore_error_log



=== TEST 6: test skip keys
skip some services, return default nodes, get response: missing consul services
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8600"
    prefix: "upstreams"
    skip_services:
      - "service_a"
    default_service:
      host: "127.0.0.1"
      port: 20999
      metadata:
        fail_timeout: 1
        weight: 1
        max_fails: 1
#END
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service_a
      discovery_type: consul
      type: roundrobin
#END
--- request
GET /hello
--- response_body eval
"missing consul services\n"
--- ignore_error_log



=== TEST 7: test register and unregister nodes
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service_a
      discovery_type: consul
      type: roundrobin
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
location /sleep {
    content_by_lua_block {
        local args = ngx.req.get_uri_args()
        local sec = args.sec or "2"
        ngx.sleep(tonumber(sec))
        ngx.say("ok")
    }
}
--- timeout: 6
--- request eval
[
    "PUT /v1/agent/service/deregister/service_a1",
    "PUT /v1/agent/service/deregister/service_a2",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30513,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_a2\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30514,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "GET /sleep",

    "GET /hello?random1",
    "GET /hello?random2",
    "GET /hello?random3",
    "GET /hello?random4",

    "PUT /v1/agent/service/deregister/service_a1",
    "PUT /v1/agent/service/deregister/service_a2",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_a2\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30512,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "GET /sleep?sec=5",

    "GET /hello?random1",
    "GET /hello?random2",
    "GET /hello?random3",
    "GET /hello?random4",

]
--- response_body_like eval
[
    qr//,
    qr//,
    qr//,
    qr//,
    qr/ok\n/,

    qr/server [3-4]\n/,
    qr/server [3-4]\n/,
    qr/server [3-4]\n/,
    qr/server [3-4]\n/,

    qr//,
    qr//,
    qr//,
    qr//,
    qr/ok\n/,

    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
    qr/server [1-2]\n/
]
--- ignore_error_log



=== TEST 8: clean nodes
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
--- request eval
[
    "PUT /v1/agent/service/deregister/service_a1",
    "PUT /v1/agent/service/deregister/service_a2",
]
--- error_code eval
[200, 200]



=== TEST 9: test consul short connect type
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
    keepalive: false
    fetch_interval: 3
    default_service:
      host: "127.0.0.1"
      port: 20999
#END
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service_a
      discovery_type: consul
      type: roundrobin
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
location /sleep {
    content_by_lua_block {
        local args = ngx.req.get_uri_args()
        local sec = args.sec or "2"
        ngx.sleep(tonumber(sec))
        ngx.say("ok")
    }
}
--- timeout: 6
--- request eval
[
    "GET /hello",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "GET /sleep?sec=5",
    "GET /hello",
]
--- response_body_like eval
[
    qr/missing consul services\n/,
    qr//,
    qr/ok\n/,
    qr/server 1\n/
]
--- ignore_error_log



=== TEST 10: retry when Consul can't be reached (long connect type)
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8501"
    keepalive: true
    fetch_interval: 3
    default_service:
      host: "127.0.0.1"
      port: 20999
#END
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service_a
      discovery_type: consul
      type: roundrobin
#END
--- timeout: 4
--- config
location /sleep {
    content_by_lua_block {
        local args = ngx.req.get_uri_args()
        local sec = args.sec or "2"
        ngx.sleep(tonumber(sec))
        ngx.say("ok")
    }
}
--- request
GET /sleep?sec=3
--- response_body
ok
--- grep_error_log eval
qr/retry connecting consul after \d seconds/
--- grep_error_log_out
retry connecting consul after 1 seconds
retry connecting consul after 4 seconds



=== TEST 11: prepare healthy and unhealthy nodes
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
--- request eval
[
    "PUT /v1/agent/service/deregister/service_a1",
    "PUT /v1/agent/service/deregister/service_a2",
    "PUT /v1/agent/service/deregister/service_b1",
    "PUT /v1/agent/service/deregister/service_b2",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_b1\",\"Name\":\"service_b\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30513,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_b2\",\"Name\":\"service_b\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30514,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
]
--- error_code eval
[200, 200, 200, 200, 200, 200]



=== TEST 12: test health checker
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
upstreams:
    -
      service_name: service_b
      discovery_type: consul
      type: roundrobin
      id: 1
      checks:
        active:
            http_path: "/hello"
            healthy:
                interval: 1
                successes: 1
            unhealthy:
                interval: 1
                http_failures: 1
#END
--- config
    location /thc {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            httpc:request_uri(uri, {method = "GET"})
            ngx.sleep(3)

            local code, body, res = t.test('/v1/healthcheck',
                ngx.HTTP_GET)
            res = json.decode(res)
            local nodes = res[1].nodes
            table.sort(nodes, function(a, b)
                return a.port < b.port
            end)
            for _, node in ipairs(nodes) do
                node.counter = nil
            end
            ngx.say(json.encode(nodes))

            local code, body, res = t.test('/v1/healthcheck/upstreams/1',
                ngx.HTTP_GET)
            res = json.decode(res)
            nodes = res.nodes
            table.sort(nodes, function(a, b)
                return a.port < b.port
            end)
            for _, node in ipairs(nodes) do
                node.counter = nil
            end
            ngx.say(json.encode(nodes))
        }
    }
--- request
GET /thc
--- response_body
[{"hostname":"127.0.0.1","ip":"127.0.0.1","port":30513,"status":"healthy"},{"hostname":"127.0.0.1","ip":"127.0.0.1","port":30514,"status":"healthy"}]
[{"hostname":"127.0.0.1","ip":"127.0.0.1","port":30513,"status":"healthy"},{"hostname":"127.0.0.1","ip":"127.0.0.1","port":30514,"status":"healthy"}]
--- ignore_error_log



=== TEST 13: test consul catalog service change
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
    keepalive: false
    fetch_interval: 3
    default_service:
      host: "127.0.0.1"
      port: 20999
#END
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service_a
      discovery_type: consul
      type: roundrobin
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}

location /sleep {
    content_by_lua_block {
        local args = ngx.req.get_uri_args()
        local sec = args.sec or "2"
        ngx.sleep(tonumber(sec))
        ngx.say("ok")
    }
}
--- timeout: 6
--- request eval
[
    "PUT /v1/agent/service/deregister/service_a1",
    "GET /sleep?sec=3",
    "GET /hello",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "GET /sleep?sec=5",
    "GET /hello",
    "PUT /v1/agent/service/deregister/service_a1",
    "GET /sleep?sec=5",
    "GET /hello",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "GET /sleep?sec=5",
    "GET /hello",
]
--- response_body_like eval
[
    qr//,
    qr/ok\n/,
    qr/missing consul services\n/,
    qr//,
    qr/ok\n/,
    qr/server 1\n/,
    qr//,
    qr/ok\n/,
    qr/missing consul services\n/,
    qr//,
    qr/ok\n/,
    qr/server 1\n/,
]
--- ignore_error_log



=== TEST 14: bootstrap acl
--- config
location /v1/acl {
    proxy_pass http://127.0.0.1:8502;
}
--- request eval
"PUT /v1/acl/bootstrap\n" . "{\"BootstrapSecret\": \"2b778dd9-f5f1-6f29-b4b4-9a5fa948757a\"}"
--- error_code_like: ^(?:200|403)$



=== TEST 15: test register and unregister nodes with acl
--- yaml_config eval: $::yaml_config_with_acl
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: service-a
      discovery_type: consul
      type: roundrobin
#END
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8502;
    proxy_set_header X-Consul-Token "2b778dd9-f5f1-6f29-b4b4-9a5fa948757a";
}
location /sleep {
    content_by_lua_block {
        local args = ngx.req.get_uri_args()
        local sec = args.sec or "2"
        ngx.sleep(tonumber(sec))
        ngx.say("ok")
    }
}
--- timeout: 6
--- pipelined_requests eval
[
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service-a1\",\"Name\":\"service-a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30513,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service-a2\",\"Name\":\"service-a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30514,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "GET /sleep",

    "GET /hello?random1",
    "GET /hello?random2",
    "GET /hello?random3",
    "GET /hello?random4",

    "PUT /v1/agent/service/deregister/service-a1",
    "PUT /v1/agent/service/deregister/service-a2",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service-a1\",\"Name\":\"service-a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service-a2\",\"Name\":\"service-a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30512,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "GET /sleep?sec=5",

    "GET /hello?random1",
    "GET /hello?random2",
    "GET /hello?random3",
    "GET /hello?random4",

    "PUT /v1/agent/service/deregister/service-a1",
    "PUT /v1/agent/service/deregister/service-a2",
]
--- response_body_like eval
[
    qr//,
    qr//,
    qr/ok\n/,

    qr/server [3-4]\n/,
    qr/server [3-4]\n/,
    qr/server [3-4]\n/,
    qr/server [3-4]\n/,

    qr//,
    qr//,
    qr//,
    qr//,
    qr/ok\n/,

    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
    qr/server [1-2]\n/,

    qr//,
    qr//
]
--- ignore_error_log



=== TEST 16: test service_name as variable in route configuration
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: "${backend}"
      discovery_type: consul
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            -- Set nginx map variable
            ngx.var.backend = "service_a"

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, { method = "GET"})
            if err then
                ngx.log(ngx.ERR, err)
                ngx.status = res.status
                return
            end
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/server [1-2]\n/
--- no_error_log
[error]



=== TEST 17: test empty variable in service_name
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: "${backend}"
      discovery_type: consul
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            -- Set empty nginx map variable
            ngx.var.backend = ""

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, { method = "GET"})
            if err then
                ngx.log(ngx.ERR, err)
                ngx.status = res.status
                return
            end
            ngx.say(res.status)
        }
    }
--- request
GET /t
--- response_body
503
--- error_log
resolve_var resolves to empty string
