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


our $yaml_config = <<_EOC_;
apisix:
  enable_control: true
  node_listen: 1984
  config_center: yaml
  enable_admin: false

discovery:
  eureka:
    host:
      - "http://127.0.0.1:8761"
    prefix: "/eureka/"
    fetch_interval: 10
    weight: 80
    timeout:
      connect: 1500
      send: 1500
      read: 1500
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
  dns:
    servers:
      - "127.0.0.1:1053"
_EOC_


run_tests();

__DATA__

=== TEST 1: test consul_kv dump_data api
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local code, body, res = t.test('/v1/discovery/consul_kv/dump',
                ngx.HTTP_GET)
            local entity = json.decode(res)
            ngx.say(json.encode(entity.services))
            ngx.say(json.encode(entity.config))
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
{}
{"fetch_interval":3,"keepalive":true,"prefix":"upstreams","servers":["http://127.0.0.1:8500","http://127.0.0.1:8600"],"timeout":{"connect":2000,"read":2000,"wait":60},"weight":1}



=== TEST 2: test eureka dump_data api
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")

            local code, body, res = t.test('/v1/discovery/eureka/dump',
                ngx.HTTP_GET, nil,
                [[{
                    "config": {
                        "fetch_interval": 10,
                        "host": [
                            "http://127.0.0.1:8761"
                        ],
                        "prefix": "/eureka/",
                        "timeout": {
                            "connect": 1500,
                            "read": 1500,
                            "send": 1500
                        },
                        "weight": 80
                    },
                    "services": {}
                }]]
                )
            ngx.satus = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
passed



=== TEST 3: test dns api
--- yaml_config eval: $::yaml_config
--- request
GET /v1/discovery/dns/dump
--- error_code: 404



=== TEST 4: test unconfigured eureka dump_data api
--- yaml_config
apisix:
  enable_control: true
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  consul_kv:
    servers:
      - "http://127.0.0.1:8500"
      - "http://127.0.0.1:8600"
#END
--- request
GET /v1/discovery/eureka/dump
--- error_code: 404



=== TEST 5: prepare consul kv register nodes
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
    "DELETE /consul1/upstreams/?recurse=true",
    "DELETE /consul2/upstreams/?recurse=true",
    "PUT /consul1/upstreams/webpages/127.0.0.1:30511\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul1/upstreams/webpages/127.0.0.1:30512\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul2/upstreams/webpages/127.0.0.1:30513\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
    "PUT /consul2/upstreams/webpages/127.0.0.1:30514\n" . "{\"weight\": 1, \"max_fails\": 2, \"fail_timeout\": 1}",
]
--- response_body eval
["true", "true", "true", "true", "true", "true"]



=== TEST 6: dump consul_kv services
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            ngx.sleep(2)

            local code, body, res = t.test('/v1/discovery/consul_kv/dump',
                ngx.HTTP_GET)
            local entity = json.decode(res)
            ngx.say(json.encode(entity.services))
        }
    }
--- request
GET /t
--- error_code: 200
--- response_body
{"http://127.0.0.1:8500/v1/kv/upstreams/webpages/":[{"host":"127.0.0.1","port":30511,"weight":1},{"host":"127.0.0.1","port":30512,"weight":1}],"http://127.0.0.1:8600/v1/kv/upstreams/webpages/":[{"host":"127.0.0.1","port":30513,"weight":1},{"host":"127.0.0.1","port":30514,"weight":1}]}



=== TEST 7: clean consul kv register nodes
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
    "DELETE /consul1/upstreams/?recurse=true",
    "DELETE /consul2/upstreams/?recurse=true"
]
--- response_body eval
["true", "true"]
