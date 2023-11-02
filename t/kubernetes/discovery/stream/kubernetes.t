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

BEGIN {
    our $token_file = "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token";
    our $token_value = eval {`cat $token_file 2>/dev/null`};

    our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes:
    - id: first
      service:
        host: "127.0.0.1"
        port: "6443"
      client:
        token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"
    - id: second
      service:
        schema: "http",
        host: "127.0.0.1",
        port: "6445"
      client:
        token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"

_EOC_

}

use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

plan('no_plan');

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

    my $main_config = $block->main_config // <<_EOC_;
env KUBERNETES_SERVICE_HOST=127.0.0.1;
env KUBERNETES_SERVICE_PORT=6443;
env KUBERNETES_CLIENT_TOKEN=$::token_value;
env KUBERNETES_CLIENT_TOKEN_FILE=$::token_file;
_EOC_

    $block->set_value("main_config", $main_config);

    my $config = $block->config // <<_EOC_;
        location /operators {
            content_by_lua_block {
                local http = require("resty.http")
                local core = require("apisix.core")
                local ipairs = ipairs

                ngx.req.read_body()
                local request_body = ngx.req.get_body_data()
                local operators = core.json.decode(request_body)

                core.log.info("get body ", request_body)
                core.log.info("get operators ", #operators)
                for _, op in ipairs(operators) do
                    local method, path, body
                    local headers = {
                        ["Host"] = "127.0.0.1:6445"
                    }

                    if op.op == "replace_subsets" then
                        method = "PATCH"
                        path = "/api/v1/namespaces/" .. op.namespace .. "/endpoints/" .. op.name
                        if #op.subsets == 0 then
                            body = '[{"path":"/subsets","op":"replace","value":[]}]'
                        else
                            local t = { { op = "replace", path = "/subsets", value = op.subsets } }
                            body = core.json.encode(t, true)
                        end
                        headers["Content-Type"] = "application/json-patch+json"
                    end

                    if op.op == "replace_labels" then
                        method = "PATCH"
                        path = "/api/v1/namespaces/" .. op.namespace .. "/endpoints/" .. op.name
                        local t = { { op = "replace", path = "/metadata/labels", value = op.labels } }
                        body = core.json.encode(t, true)
                        headers["Content-Type"] = "application/json-patch+json"
                    end

                    local httpc = http.new()
                    core.log.info("begin to connect ", "127.0.0.1:6445")
                    local ok, message = httpc:connect({
                        scheme = "http",
                        host = "127.0.0.1",
                        port = 6445,
                    })
                    if not ok then
                        core.log.error("connect 127.0.0.1:6445 failed, message : ", message)
                        ngx.say("FAILED")
                    end
                    local res, err = httpc:request({
                        method = method,
                        path = path,
                        headers = headers,
                        body = body,
                    })
                    if err ~= nil then
                        core.log.err("operator k8s cluster error: ", err)
                        return 500
                    end
                    if res.status ~= 200 and res.status ~= 201 and res.status ~= 409 then
                        return res.status
                    end
                end
                ngx.say("DONE")
            }
        }

_EOC_

    $block->set_value("config", $config);

    my $stream_config = $block->stream_config // <<_EOC_;
        server {
            listen 8125;
            content_by_lua_block {
                local core = require("apisix.core")
                local d = require("apisix.discovery.kubernetes")

                ngx.sleep(1)

                local sock = ngx.req.socket()
                local request_body = sock:receive()

                core.log.info("get body ", request_body)

                local response_body = "{"
                local queries = core.json.decode(request_body)
                for _,query in ipairs(queries) do
                  local nodes = d.nodes(query)
                  if nodes==nil or #nodes==0 then
                      response_body=response_body.." "..0
                  else
                      response_body=response_body.." "..#nodes
                  end
                end
                ngx.say(response_body.." }")
            }
        }

_EOC_

  $block->set_value("extra_stream_config", $stream_config);

});

run_tests();

__DATA__

=== TEST 1: create namespace and endpoints
--- yaml_config eval: $::yaml_config
--- request
POST /operators
[
  {
    "op": "replace_subsets",
    "namespace": "ns-a",
    "name": "ep",
    "subsets": [
      {
        "addresses": [
          {
            "ip": "10.0.0.1"
          },
          {
            "ip": "10.0.0.2"
          }
        ],
        "ports": [
          {
            "name": "p1",
            "port": 5001
          }
        ]
      },
      {
        "addresses": [
          {
            "ip": "20.0.0.1"
          },
          {
            "ip": "20.0.0.2"
          }
        ],
        "ports": [
          {
            "name": "p2",
            "port": 5002
          }
        ]
      }
    ]
  },
  {
    "op": "create_namespace",
    "name": "ns-b"
  },
  {
    "op": "replace_subsets",
    "namespace": "ns-b",
    "name": "ep",
    "subsets": [
      {
        "addresses": [
          {
            "ip": "10.0.0.1"
          },
          {
            "ip": "10.0.0.2"
          }
        ],
        "ports": [
          {
            "name": "p1",
            "port": 5001
          }
        ]
      },
      {
        "addresses": [
          {
            "ip": "20.0.0.1"
          },
          {
            "ip": "20.0.0.2"
          }
        ],
        "ports": [
          {
            "name": "p2",
            "port": 5002
          }
        ]
      }
    ]
  },
  {
    "op": "create_namespace",
    "name": "ns-c"
  },
  {
    "op": "replace_subsets",
    "namespace": "ns-c",
    "name": "ep",
    "subsets": [
      {
        "addresses": [
          {
            "ip": "10.0.0.1"
          },
          {
            "ip": "10.0.0.2"
          }
        ],
        "ports": [
          {
            "port": 5001
          }
        ]
      },
      {
        "addresses": [
          {
            "ip": "20.0.0.1"
          },
          {
            "ip": "20.0.0.2"
          }
        ],
        "ports": [
          {
            "port": 5002
          }
        ]
      }
    ]
  }
]
--- more_headers
Content-type: application/json



=== TEST 2: use default parameters
--- yaml_config eval: $::yaml_config
--- apisix_yaml
stream_routes:
  -
    id: 1
    server_port: 1985
    upstream_id: 1

upstreams:
  - nodes:
      "127.0.0.1:8125": 1
    type: roundrobin
    id: 1

#END
--- stream_request
["first/ns-a/ep:p1","first/ns-a/ep:p2","first/ns-b/ep:p1","second/ns-a/ep:p1","second/ns-a/ep:p2","second/ns-b/ep:p1"]
--- stream_response eval
qr{ 2 2 2 2 2 2 }
