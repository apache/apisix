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
no_long_string();
no_root_location();
no_shuffle();
log_level("info");


add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;

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

run_tests();

__DATA__

=== TEST 1: prepare nodes
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
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /v1/agent/service/register\n" . "{\"ID\":\"service_b1\",\"Name\":\"service_b\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":8002,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
]
--- response_body eval
--- error_code eval
[200, 200, 200, 200, 200, 200]



=== TEST 2: show dump services
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
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
{"service_a":[{"host":"127.0.0.1","port":30511,"weight":1}],"service_b":[{"host":"127.0.0.1","port":8002,"weight":1}]}



=== TEST 3: prepare dump file for next test
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
    dump:
      path: "/tmp/consul.dump"
      load_on_init: false
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
--- response_body
server 1



=== TEST 4: clean registered nodes
--- config
location /v1/agent {
    proxy_pass http://127.0.0.1:8500;
}
--- request eval
[
    "PUT /v1/agent/service/deregister/service_a1",
    "PUT /v1/agent/service/deregister/service_b1",
]
--- error_code eval
[200, 200]



=== TEST 5: test load dump on init
Configure the invalid consul server addr, and loading the last test 3 generated /tmp/consul.dump file into memory when initializing
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul.dump"
      load_on_init: true
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
--- response_body
server 1
--- error_log
connect consul



=== TEST 6: delete dump file
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.cli.util")
            local succ, err = util.execute_cmd("rm -f /tmp/consul.dump")
            ngx.say(succ and "success" or err)
        }
    }
--- request
GET /t
--- response_body
success



=== TEST 7: miss load dump on init
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul.dump"
      load_on_init: true
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
--- error_code: 503
--- error_log
connect consul
fetch nodes failed
failed to set upstream



=== TEST 8: prepare expired dump file
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.cli.util")
            local json = require("toolkit.json")

            local applications = json.decode('{"service_a":[{"host":"127.0.0.1","port":30511,"weight":1}]}')
            local entity = {
                services = applications,
                last_update = ngx.time(),
                expire = 10,
            }
            local succ, err =  util.write_file("/tmp/consul.dump", json.encode(entity))

            ngx.sleep(2)
            ngx.say(succ and "success" or err)
        }
    }
--- timeout: 3
--- request
GET /t
--- response_body
success



=== TEST 9: unexpired dump
test load unexpired /tmp/consul.dump file generated by upper test when initializing
 when initializing
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul.dump"
      load_on_init: true
      expire: 5
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
--- response_body
server 1
--- error_log
connect consul



=== TEST 10: expired dump
test load expired ( by check: (dump_file.last_update + dump.expire) < ngx.time ) ) /tmp/consul.dump file generated by upper test when initializing
 when initializing
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul.dump"
      load_on_init: true
      expire: 1
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
--- error_code: 503
--- error_log
dump file: /tmp/consul.dump had expired, ignored it



=== TEST 11: delete dump file
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.cli.util")
            local succ, err = util.execute_cmd("rm -f /tmp/consul.dump")
            ngx.say(succ and "success" or err)
        }
    }
--- request
GET /t
--- response_body
success



=== TEST 12: dump file inexistence
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul.dump"
#END
--- request
GET /v1/discovery/consul/show_dump_file
--- error_code: 503
--- error_log
connect consul



=== TEST 13: no dump config
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:38500"
#END
--- request
GET /v1/discovery/consul/show_dump_file
--- error_code: 503
--- error_log
connect consul



=== TEST 14: prepare nodes with different consul clusters
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
    "PUT /consul2/register\n" . "{\"ID\":\"service_b1\",\"Name\":\"service_b\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30517,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
]
--- error_code eval
[200, 200, 200, 200, 200, 200, 200, 200, 200, 200]



=== TEST 15: show dump services with different consul clusters
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
    dump:
      path: "consul.dump"
      load_on_init: false
--- config
    location /bonjour {
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
GET /bonjour
--- response_body
{"service_a":[{"host":"127.0.0.1","port":30511,"weight":1}],"service_b":[{"host":"127.0.0.1","port":30517,"weight":1}]}



=== TEST 16: prepare nodes with consul health check
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
    "PUT /v1/agent/service/register\n" . "{\"Checks\": [{\"http\": \"http://baidu.com\",\"interval\": \"1s\"}],\"ID\":\"service_a1\",\"Name\":\"service_a\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":30511,\"Meta\":{\"service_a_version\":\"4.0\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
    "PUT /v1/agent/service/register\n" . "{\"Checks\": [{\"http\": \"http://127.0.0.1:8002\",\"interval\": \"1s\"}],\"ID\":\"service_b1\",\"Name\":\"service_b\",\"Tags\":[\"primary\",\"v1\"],\"Address\":\"127.0.0.1\",\"Port\":8002,\"Meta\":{\"service_b_version\":\"4.1\"},\"EnableTagOverride\":false,\"Weights\":{\"Passing\":10,\"Warning\":1}}",
]
--- response_body eval
--- error_code eval
[200, 200, 200, 200, 200, 200]
--- wait: 2



=== TEST 17: show dump services with consul health check
--- yaml_config
apisix:
  node_listen: 1984
  enable_control: true
discovery:
  consul:
    servers:
      - "http://127.0.0.1:8500"
    dump:
      path: "consul.dump"
      load_on_init: false
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            for i = 1, 3 do
                ngx.sleep(2)
                local code, body, res = t.test('/v1/discovery/consul/show_dump_file',
                    ngx.HTTP_GET)
                local entity = json.decode(res)
                if entity.services and entity.services.service_a then
                    ngx.say(json.encode(entity.services))
                    return
                end
            end
        }
    }
--- timeout: 8
--- request
GET /t
--- response_body
{"service_a":[{"host":"127.0.0.1","port":30511,"weight":1}]}
