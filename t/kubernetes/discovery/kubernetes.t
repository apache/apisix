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
log_level('warn');
no_root_location();
no_shuffle();
workers(4);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $apisix_yaml = $block->apisix_yaml // <<_EOC_;
routes: []
#END
_EOC_

    $block->set_value("apisix_yaml", $apisix_yaml);

    my $config = $block->config // <<_EOC_;

        location /compare {
            content_by_lua_block {
                local http = require("resty.http")
                local core = require("apisix.core")
                local local_conf = require("apisix.core.config_local").local_conf()

                local function deep_compare(tbl1, tbl2)
                    if tbl1 == tbl2 then
                        return true
                    elseif type(tbl1) == "table" and type(tbl2) == "table" then
                        for key1, value1 in pairs(tbl1) do
                            local value2 = tbl2[key1]
                            if value2 == nil then
                                -- avoid the type call for missing keys in tbl2 by directly comparing with nil
                                return false
                            elseif value1 ~= value2 then
                                if type(value1) == "table" and type(value2) == "table" then
                                    if not deep_compare(value1, value2) then
                                        return false
                                    end
                                else
                                    return false
                                end
                            end
                        end
                        for key2, _ in pairs(tbl2) do
                            if tbl1[key2] == nil then
                                return false
                            end
                        end
                        return true
                    end

                    return false
                end

                ngx.req.read_body()
                local request_body = ngx.req.get_body_data()
                local expect = core.json.decode(request_body)
                local current = local_conf.discovery.kubernetes
                if deep_compare(expect,current) then
                  ngx.say("true")
                else
                  ngx.say("false, current is ",core.json.encode(current,true))
                end
            }
        }

_EOC_

    $block->set_value("config", $config);

});

run_tests();

__DATA__

=== TEST 1: default value with minimal configuration
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes: {}
--- request
GET /compare
{
  "service": {
    "schema": "https",
    "host": "${KUBERNETES_SERVICE_HOST}",
    "port": "${KUBERNETES_SERVICE_PORT}"
  },
  "client": {
    "token_file": "/var/run/secrets/kubernetes.io/serviceaccount/token"
  },
  "shared_size": "1m",
  "default_weight": 50
}
--- more_headers
Content-type: application/json
--- response_body
true



=== TEST 2: default value with minimal service and client configuration
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes:
    service: {}
    client: {}
--- request
GET /compare
{
  "service": {
    "schema": "https",
    "host": "${KUBERNETES_SERVICE_HOST}",
    "port": "${KUBERNETES_SERVICE_PORT}"
  },
  "client": {
    "token_file": "/var/run/secrets/kubernetes.io/serviceaccount/token"
  },
  "shared_size": "1m",
  "default_weight": 50
}
--- more_headers
Content-type: application/json
--- response_body
true



=== TEST 3: mixing set custom and default values
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes:
    service:
        host: "sample.com"
    shared_size: "2m"
--- request
GET /compare
{
  "service": {
    "schema": "https",
    "host": "sample.com",
    "port": "${KUBERNETES_SERVICE_PORT}"
  },
  "client": {
    "token_file" : "/var/run/secrets/kubernetes.io/serviceaccount/token"
  },
  "shared_size": "2m",
  "default_weight": 50
}
--- more_headers
Content-type: application/json
--- response_body
true



=== TEST 4: mixing set custom and default values
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes:
    service:
        schema: "http"
    client:
        token: "test"
    default_weight: 33
--- request
GET /compare
{
  "service": {
    "schema": "http",
    "host": "${KUBERNETES_SERVICE_HOST}",
    "port": "${KUBERNETES_SERVICE_PORT}"
  },
  "client": {
    "token": "test"
  },
  "shared_size": "1m",
  "default_weight": 33
}
--- more_headers
Content-type: application/json
--- response_body
true



=== TEST 5: multi cluster mode configuration
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes:
  - id: "debug"
    service:
        host: "1.cluster.com"
        port: "6445"
    client:
        token: "token"
  - id: "release"
    service:
        schema: "http"
        host: "2.cluster.com"
        port: "${MyPort}"
    client:
        token_file: "/var/token"
    default_weight: 33
    shared_size: "2m"
--- request
GET /compare
[
  {
    "id": "debug",
    "service": {
      "schema": "https",
      "host": "1.cluster.com",
      "port": "6445"
    },
    "client": {
      "token": "token"
    },
    "default_weight": 50,
    "shared_size": "1m"
  },
  {
    "id": "release",
    "service": {
      "schema": "http",
      "host": "2.cluster.com",
      "port": "${MyPort}"
    },
    "client": {
      "token_file": "/var/token"
    },
    "default_weight": 33,
    "shared_size": "2m"
  }
]
--- more_headers
Content-type: application/json
--- response_body
true
