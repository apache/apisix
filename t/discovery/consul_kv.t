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

    server {
        listen 20999;

        location / {
            content_by_lua_block {
                ngx.say("missing consul_kv services")
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
  config_center: yaml
  enable_admin: false

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
    prefix: "upstreams"
    skip_keys:
      - "upstreams/unused_api/"
    timeout:
      connect: 1000
      read: 1000
      wait: 60
    weight: 1
    fetch_interval: 5
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

=== TEST 1: prepare consul kv register nodes
--- config
location /consul1 {
    rewrite  ^/consul1/(.*) /v1/kv/$1 break;
    proxy_pass http://127.0.0.1:8500;
}

location /consul2 {
    rewrite  ^/consul2/(.*) /v1/kv/$1 break;
    proxy_pass http://127.0.0.1:8600;
}
--- pipelined_requests eval
[
    "DELETE /consul1/upstreams/webpages/?recurse=true",
    "DELETE /consul2/upstreams/webpages/?recurse=true",
    "PUT /consul1/upstreams/webpages/127.0.0.1:30511\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul1/upstreams/webpages/127.0.0.1:30512\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul2/upstreams/webpages/127.0.0.1:30513\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul2/upstreams/webpages/127.0.0.1:30514\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
]
--- response_body eval
["true", "true", "true", "true", "true", "true"]



=== TEST 2: test consul server 1
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: http://127.0.0.1:8500/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
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
      service_name: http://127.0.0.1:8600/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
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



=== TEST 4: test mini consul_kv config
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:6500"
#END
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: http://127.0.0.1:8500/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
      type: roundrobin
#END
--- request
GET /hello
--- response_body_like eval
qr/server [1-2]/



=== TEST 5: test invalid service name
sometimes the consul key maybe deleted by mistake

--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: http://127.0.0.1:8600/v1/kv/upstreams/deleted_keys/
      discovery_type: consul_kv
      type: roundrobin
#END
--- pipelined_requests eval
[
    "GET /hello_api",
    "GET /hello_api"
]
--- response_body eval
[
    "missing consul_kv services\n",
    "missing consul_kv services\n"
]
--- grep_error_log_out eval
[
    "fetch nodes failed by http://127.0.0.1:8600/v1/kv/upstreams/deleted_keys/, return default service",
    "fetch nodes failed by http://127.0.0.1:8600/v1/kv/upstreams/deleted_keys/, return default service"
]



=== TEST 6: test skip keys
skip some keys, return default nodes, get response: missing consul_kv services
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8600"
    prefix: "upstreams"
    skip_keys:
      - "upstreams/webpages/"
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
      service_name: http://127.0.0.1:8600/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
      type: roundrobin
#END
--- request
GET /hello
--- response_body eval
"missing consul_kv services\n"



=== TEST 7: test register and unregister nodes
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    upstream:
      service_name: http://127.0.0.1:8500/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
      type: roundrobin
#END
--- config
location /v1/kv {
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
    "DELETE /v1/kv/upstreams/webpages/?recurse=true",
    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30511\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "GET /sleep?sec=5",
    "GET /hello",

    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30512\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "GET /sleep",
    "GET /hello",
    "GET /hello",

    "DELETE /v1/kv/upstreams/webpages/127.0.0.1:30511",
    "DELETE /v1/kv/upstreams/webpages/127.0.0.1:30512",
    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30513\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30514\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "GET /sleep",

    "GET /hello?random1",
    "GET /hello?random2",
    "GET /hello?random3",
    "GET /hello?random4",

    "DELETE /v1/kv/upstreams/webpages/127.0.0.1:30513",
    "DELETE /v1/kv/upstreams/webpages/127.0.0.1:30514",
    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30511\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30512\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "GET /sleep?sec=5",

    "GET /hello?random1",
    "GET /hello?random2",
    "GET /hello?random3",
    "GET /hello?random4",

]
--- response_body_like eval
[
    qr/true/,
    qr/true/,
    qr/ok\n/,
    qr/server 1\n/,

    qr/true/,
    qr/ok\n/,
    qr/server [1-2]\n/,
    qr/server [1-2]\n/,

    qr/true/,
    qr/true/,
    qr/true/,
    qr/true/,
    qr/ok\n/,

    qr/server [3-4]\n/,
    qr/server [3-4]\n/,
    qr/server [3-4]\n/,
    qr/server [3-4]\n/,

    qr/true/,
    qr/true/,
    qr/true/,
    qr/true/,
    qr/ok\n/,

    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
    qr/server [1-2]\n/,
    qr/server [1-2]\n/
]



=== TEST 8: prepare healthy and unhealthy nodes
--- config
location /v1/kv {
    proxy_pass http://127.0.0.1:8500;
}
--- request eval
[
    "DELETE /v1/kv/upstreams/webpages/?recurse=true",
    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30511\n" . "{\"weight\": 1, \"max_fails\": 1, \"fail_timeout\": 1}",
    "PUT /v1/kv/upstreams/webpages/127.0.0.2:1988\n" . "{\"weight\": 1, \"max_fails\": 1, \"fail_timeout\": 1}",
]
--- response_body eval
[
    'true',
    'true',
    'true',
]



=== TEST 9: test health checker
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
upstreams:
    -
      service_name: http://127.0.0.1:8500/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
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
            ngx.sleep(9)

            local code, body, res = t.test('/v1/healthcheck',
                ngx.HTTP_GET)
            res = json.decode(res)
            table.sort(res[1].nodes, function(a, b)
                return a.host < b.host
            end)
            ngx.say(json.encode(res))

            local code, body, res = t.test('/v1/healthcheck/upstreams/1',
                ngx.HTTP_GET)
            res = json.decode(res)
            table.sort(res.nodes, function(a, b)
                return a.host < b.host
            end)
            ngx.say(json.encode(res))
        }
    }
--- timeout: 12
--- request
GET /thc
--- response_body
[{"healthy_nodes":[{"host":"127.0.0.1","port":30511,"weight":1}],"name":"upstream#/upstreams/1","nodes":[{"host":"127.0.0.1","port":30511,"weight":1},{"host":"127.0.0.2","port":1988,"weight":1}],"src_id":"1","src_type":"upstreams"}]
{"healthy_nodes":[{"host":"127.0.0.1","port":30511,"weight":1}],"name":"upstream#/upstreams/1","nodes":[{"host":"127.0.0.1","port":30511,"weight":1},{"host":"127.0.0.2","port":1988,"weight":1}],"src_id":"1","src_type":"upstreams"}



=== TEST 10: clean nodes
--- config
location /v1/kv {
    proxy_pass http://127.0.0.1:8500;
}
--- request eval
[
    "DELETE /v1/kv/upstreams/webpages/?recurse=true"
]
--- response_body eval
[
    'true'
]



=== TEST 11: test consul_kv short connect type
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false

discovery:
  consul_kv:
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
      service_name: http://127.0.0.1:8500/v1/kv/upstreams/webpages/
      discovery_type: consul_kv
      type: roundrobin
#END
--- config
location /v1/kv {
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
    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30511\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "GET /sleep?sec=5",
    "GET /hello",
]
--- response_body_like eval
[
    qr/missing consul_kv services\n/,
    qr/true/,
    qr/ok\n/,
    qr/server 1\n/
]
