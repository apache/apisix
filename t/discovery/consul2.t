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


run_tests();

__DATA__

=== TEST 1: sanity
--- config
location /consul1 {
    rewrite  ^/consul1/(.*) /v1/agent/service/$1 break;
    proxy_pass http://127.0.0.1:9500;
}

location /consul2 {
    rewrite  ^/consul2/(.*) /v1/agent/service/$1 break;
    proxy_pass http://127.0.0.1:9501;
}
location /consul3 {
    rewrite  ^/consul3/(.*) /v1/agent/service/$1 break;
    proxy_pass http://127.0.0.1:9502;
}
--- pipelined_requests eval
[
    "PUT /consul1/deregister/service_a1",
    "PUT /consul1/deregister/service_b1",
    "PUT /consul1/deregister/service_a2",
    "PUT /consul1/deregister/service_b2",
    "PUT /consul1/deregister/service_a3",
    "PUT /consul1/deregister/service_a4",
    "PUT /consul1/deregister/service_no_port",
    "PUT /consul2/deregister/service_a1",
    "PUT /consul2/deregister/service_a2",
    "PUT /consul3/deregister/service_a1",
    "PUT /consul3/deregister/service_a2",
    "PUT /consul1/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul1/register\n" . "{\"ID\":\"service_a2\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30512,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul1/register\n" . "{\"ID\":\"service_a3\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"localhost\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul1/register\n" . "{\"ID\":\"service_a4\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"localhost\",\"Port\":30512,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul1/register\n" . "{\"ID\":\"service_no_port\",\"Name\":\"service_no_port\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Meta\":{\"service_version\":\"1.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul2/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul2/register\n" . "{\"ID\":\"service_a2\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30512,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul3/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /consul3/register\n" . "{\"ID\":\"service_a2\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30512,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
]
--- error_code eval
[200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200]



=== TEST 2: show dump services without duplicates
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:9500"
    dump:
      path: "consul.dump"
      load_on_init: false
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            ngx.sleep(2)

            local code, body, res = t.test('/v1/discovery/consul/show_dump_file',
                ngx.HTTP_GET)
            local entity = json.decode(res)
            ngx.say(json.encode(entity.services))
        }
    }
--- timeout: 3
--- request
GET /t
--- response_body
{"service_a":[{"host":"127.0.0.1","port":30511,"weight":1},{"host":"127.0.0.1","port":30512,"weight":1},{"host":"localhost","port":30511,"weight":1},{"host":"localhost","port":30512,"weight":1}],"service_no_port":[{"host":"127.0.0.1","port":80,"weight":1}]}



=== TEST 3: show dump services with host_sort
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:9500"
    sort_type: host_sort
    dump:
      path: "consul.dump"
      load_on_init: false
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            ngx.sleep(2)

            local code, body, res = t.test('/v1/discovery/consul/show_dump_file',
                ngx.HTTP_GET)
            local entity = json.decode(res)
            ngx.say(json.encode(entity.services))
        }
    }
--- timeout: 3
--- request
GET /t
--- response_body
{"service_a":[{"host":"127.0.0.1","port":30511,"weight":1},{"host":"127.0.0.1","port":30512,"weight":1},{"host":"localhost","port":30511,"weight":1},{"host":"localhost","port":30512,"weight":1}],"service_no_port":[{"host":"127.0.0.1","port":80,"weight":1}]}



=== TEST 4: show dump services with port sort
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:9500"
    sort_type: port_sort
    dump:
      path: "consul.dump"
      load_on_init: false
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            ngx.sleep(2)

            local code, body, res = t.test('/v1/discovery/consul/show_dump_file',
                ngx.HTTP_GET)
            local entity = json.decode(res)
            ngx.say(json.encode(entity.services))
        }
    }
--- timeout: 3
--- request
GET /t
--- response_body
{"service_a":[{"host":"127.0.0.1","port":30511,"weight":1},{"host":"localhost","port":30511,"weight":1},{"host":"127.0.0.1","port":30512,"weight":1},{"host":"localhost","port":30512,"weight":1}],"service_no_port":[{"host":"127.0.0.1","port":80,"weight":1}]}



=== TEST 5: show dump services with combine sort
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:9500"
    sort_type: combine_sort
    dump:
      path: "consul.dump"
      load_on_init: false
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            ngx.sleep(2)

            local code, body, res = t.test('/v1/discovery/consul/show_dump_file',
                ngx.HTTP_GET)
            local entity = json.decode(res)
            ngx.say(json.encode(entity.services))
        }
    }
--- timeout: 3
--- request
GET /t
--- response_body
{"service_a":[{"host":"127.0.0.1","port":30511,"weight":1},{"host":"127.0.0.1","port":30512,"weight":1},{"host":"localhost","port":30511,"weight":1},{"host":"localhost","port":30512,"weight":1}],"service_no_port":[{"host":"127.0.0.1","port":80,"weight":1}]}



=== TEST 6: verify service without port defaults to port 80
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:9500"
    dump:
      path: "consul.dump"
      load_on_init: false
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            ngx.sleep(2)

            local code, body, res = t.test('/v1/discovery/consul/show_dump_file',
                ngx.HTTP_GET)
            local entity = json.decode(res)
            
            -- Check that service_no_port exists and has default port 80
            local service_no_port = entity.services.service_no_port
            if service_no_port and #service_no_port > 0 then
                ngx.say("service_no_port found with port: ", service_no_port[1].port)
            else
                ngx.say("service_no_port not found")
            end
        }
    }
--- timeout: 3
--- request
GET /t
--- response_body
service_no_port found with port: 80
