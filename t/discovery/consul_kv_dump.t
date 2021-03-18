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

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
  enable_control: true

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
    dump:
      path: "consul_kv.dump"
      load_on_init: true
_EOC_


run_tests();

__DATA__

=== TEST 1: prepare nodes
--- config
location /v1/kv {
    proxy_pass http://127.0.0.1:8500;
}
--- request eval
[
    "DELETE /v1/kv/upstreams/?recurse=true",
    "PUT /v1/kv/upstreams/webpages/127.0.0.1:30511\n" . "{\"weight\": 1, \"max_fails\": 1, \"fail_timeout\": 1}",
]
--- response_body eval
[
    'true',
    'true',
    'true',
]



=== TEST 2: show dump services
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            ngx.sleep(2)

            local code, body, res = t.test('/v1/discovery/consul_kv/show_dump_file',
                ngx.HTTP_GET)
            local entity = json.decode(res)
            ngx.say(json.encode(entity.services))
        }
    }
--- timeout: 3
--- request
GET /t
--- response_body
{"http://127.0.0.1:8500/v1/kv/upstreams/webpages/":[{"host":"127.0.0.1","port":30511,"weight":1}]}



=== TEST 3: prepare dump file for next test
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
  enable_control: true

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
    dump:
      path: "/tmp/consul_kv.dump"
      load_on_init: true
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
--- request
GET /hello
--- response_body
server 1



=== TEST 4: clean registered nodes
--- config
location /v1/kv {
    proxy_pass http://127.0.0.1:8500;
}
--- request eval
[
    "DELETE /v1/kv/upstreams/?recurse=true",
]
--- response_body eval
[
    'true'
]



=== TEST 5: test load dump on init
Configure the invalid consul server addr, and loading the last test 3 generated /tmp/consul_kv.dump file into memory when initializing
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
  enable_control: true

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul_kv.dump"
      load_on_init: true
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
--- request
GET /hello
--- response_body
server 1



=== TEST 6: delete dump file
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.cli.util")
            local succ, err = util.execute_cmd("rm -f /tmp/consul_kv.dump")
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
  config_center: yaml
  enable_admin: false
  enable_control: true

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul_kv.dump"
      load_on_init: true
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
--- request
GET /hello
--- error_code: 503



=== TEST 8: prepare expired dump file
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.cli.util")
            local json = require("toolkit.json")

            local applications = json.decode('{"http://127.0.0.1:8500/v1/kv/upstreams/webpages/":[{"host":"127.0.0.1","port":30511,"weight":1}]}')
            local entity = {
                services = applications,
                last_update = ngx.time(),
                expire = 10,
            }
            local succ, err =  util.write_file("/tmp/consul_kv.dump", json.encode(entity))

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
test load unexpired /tmp/consul_kv.dump file generated by upper test when initializing
 when initializing
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
  enable_control: true

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul_kv.dump"
      load_on_init: true
      expire: 5
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
--- request
GET /hello
--- response_body
server 1



=== TEST 10: expired dump
test load expired ( by check: (dump_file.last_update + dump.expire) < ngx.time ) ) /tmp/consul_kv.dump file generated by upper test when initializing
 when initializing
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
  enable_control: true

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul_kv.dump"
      load_on_init: true
      expire: 1
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
--- request
GET /hello
--- error_code: 503
--- error_log
dump file: /tmp/consul_kv.dump had expired, ignored it



=== TEST 11: delete dump file
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.cli.util")
            local succ, err = util.execute_cmd("rm -f /tmp/consul_kv.dump")
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
  config_center: yaml
  enable_admin: false
  enable_control: true

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:38500"
    dump:
      path: "/tmp/consul_kv.dump"
#END
--- request
GET /v1/discovery/consul_kv/show_dump_file
--- error_code: 503



=== TEST 13: no dump config
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
  enable_control: true

discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:38500"
#END
--- request
GET /v1/discovery/consul_kv/show_dump_file
--- error_code: 503
