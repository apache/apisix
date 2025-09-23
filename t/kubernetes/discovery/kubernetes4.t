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
      watch_endpoint_slices: true
    - id: second
      service:
        schema: "http"
        host: "127.0.0.1"
        port: "6445"
      client:
        token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"
      watch_endpoint_slices: true

_EOC_

    our $single_yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes:
    service:
      host: "127.0.0.1"
      port: "6443"
    client:
      token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"
    watch_endpoint_slices: true
_EOC_

}

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

    my $main_config = $block->main_config // <<_EOC_;
env KUBERNETES_SERVICE_HOST=127.0.0.1;
env KUBERNETES_SERVICE_PORT=6443;
env KUBERNETES_CLIENT_TOKEN=$::token_value;
env KUBERNETES_CLIENT_TOKEN_FILE=$::token_file;
_EOC_

    $block->set_value("main_config", $main_config);

    my $config = $block->config // <<_EOC_;
        location /queries {
            content_by_lua_block {
              local core = require("apisix.core")
              local d = require("apisix.discovery.kubernetes")

              ngx.sleep(1)

              ngx.req.read_body()
              local request_body = ngx.req.get_body_data()
              local queries = core.json.decode(request_body)
              local response_body = "{"
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

                    if op.op == "replace_endpointslices" then
                        method = "PATCH"
                        path = "/apis/discovery.k8s.io/v1/namespaces/" .. op.namespace .. "/endpointslices/" .. op.name
                        if #op.endpoints == 0 then
                            body = '[{"path":"/endpoints","op":"replace","value":[]}]'
                        else
                            local t = { { op = "replace", path = "/endpoints", value = op.endpoints }, { op = "replace", path = "/ports", value = op.ports } }
                            body = core.json.encode(t, true)
                        end
                        headers["Content-Type"] = "application/json-patch+json"

                    elseif op.op == "create_endpointslices" then
                        method = "POST"
                        path = "/apis/discovery.k8s.io/v1/namespaces/" .. op.namespace .. "/endpointslices"
                        op.op = nil
                        op.namespace = nil
                        body = core.json.encode(op, true)

                    elseif op.op == "delete_endpointslices" then
                        method = "DELETE"
                        path = "/apis/discovery.k8s.io/v1/namespaces/" .. op.namespace .. "/endpointslices/" .. op.name
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

                    ngx.sleep(1)

                    if res.status ~= 200 and res.status ~= 201 and res.status ~= 409 then
                        return res.status
                    end
                end
                ngx.say("DONE")
            }
        }

_EOC_

    $block->set_value("config", $config);

});

run_tests();

__DATA__

=== TEST 1: endpointSlice1 update
--- yaml_config eval: $::yaml_config
--- request
POST /operators
[
    {
        "op": "replace_endpointslices",
        "namespace": "ns-a",
        "name": "service-a-epslice1",
        "metadata": {
            "labels": {
                "kubernetes.io/service-name": "service-a"
            }
        },
        "endpoints": [
            {
                "addresses": [
                    "10.0.0.1"
                ],
                "conditions": {
                    "ready": true,
                    "serving": true,
                    "terminating": false
                },
                "nodeName": "service-a-node1"
            },
            {
                "addresses": [
                    "10.0.0.2"
                ],
                "conditions": {
                    "ready": true,
                    "serving": true,
                    "terminating": false
                },
                "nodeName": "service-a-node2"
            },
            {
                "addresses": [
                    "10.0.0.3"
                ],
                "conditions": {
                    "ready": true,
                    "serving": true,
                    "terminating": false
                },
                "nodeName": "service-a-node3"
            }
        ],
        "ports": [
            {
                "name": "p1",
                "port": 5001
            }
        ]
    }
]
--- more_headers
Content-type: application/json
--- response_body
DONE



=== TEST 2: test multi-k8s watching endpointSlices
--- yaml_config eval: $::yaml_config
--- request
GET /queries
[
  "first/ns-a/service-a:p1"
]
--- more_headers
Content-type: application/json
--- response_body eval
qr{ 3 }



=== TEST 3: test single-k8s watching endpointSlices
--- yaml_config eval: $::single_yaml_config
--- request
GET /queries
[
  "ns-a/service-a:p1"
]
--- more_headers
Content-type: application/json
--- response_body eval
qr{ 3 }



=== TEST 4: endpointSlice2 create and delete for multi-k8s mode
--- yaml_config eval: $::yaml_config
--- request eval
[

"POST /operators
[
    {
        \"op\": \"create_endpointslices\",
        \"namespace\": \"ns-a\",
        \"apiVersion\": \"discovery.k8s.io/v1\",
        \"kind\": \"EndpointSlice\",
        \"metadata\": {
            \"name\": \"service-a-epslice2\",
            \"labels\": {
                \"kubernetes.io/service-name\": \"service-a\"
            }
        },
        \"addressType\": \"IPv4\",
        \"endpoints\": [
            {
                \"addresses\": [
                    \"10.0.0.4\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node4\"
            },
            {
                \"addresses\": [
                    \"10.0.0.5\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node5\"
            }
        ],
        \"ports\": [
            {
                \"name\": \"p1\",
                \"port\": 5001
            }
        ]
    }
]",

"GET /queries
[
  \"first/ns-a/service-a:p1\"
]",

"POST /operators
[
    {
        \"op\": \"delete_endpointslices\",
        \"namespace\": \"ns-a\",
        \"name\": \"service-a-epslice2\"
    }
]",

"GET /queries
[
  \"first/ns-a/service-a:p1\"
]",

]
--- more_headers
Content-type: application/json
--- response_body eval
[
    "DONE\n",
    "{ 5 }\n",
    "DONE\n",
    "{ 3 }\n",
]



=== TEST 5: endpointSlice2 create and delete for single-k8s mode
--- yaml_config eval: $::single_yaml_config
--- request eval
[

"POST /operators
[
    {
        \"op\": \"create_endpointslices\",
        \"namespace\": \"ns-a\",
        \"apiVersion\": \"discovery.k8s.io/v1\",
        \"kind\": \"EndpointSlice\",
        \"metadata\": {
            \"name\": \"service-a-epslice2\",
            \"labels\": {
                \"kubernetes.io/service-name\": \"service-a\"
            }
        },
        \"addressType\": \"IPv4\",
        \"endpoints\": [
            {
                \"addresses\": [
                    \"10.0.0.4\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node4\"
            },
            {
                \"addresses\": [
                    \"10.0.0.5\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node5\"
            }
        ],
        \"ports\": [
            {
                \"name\": \"p1\",
                \"port\": 5001
            }
        ]
    }
]",

"GET /queries
[
  \"ns-a/service-a:p1\"
]",

"POST /operators
[
    {
        \"op\": \"delete_endpointslices\",
        \"namespace\": \"ns-a\",
        \"name\": \"service-a-epslice2\"
    }
]",

"GET /queries
[
  \"ns-a/service-a:p1\"
]",

]
--- more_headers
Content-type: application/json
--- response_body eval
[
    "DONE\n",
    "{ 5 }\n",
    "DONE\n",
    "{ 3 }\n",
]



=== TEST 6: endpointSlice scale for multi-k8s mode
--- yaml_config eval: $::yaml_config
--- request eval
[

"POST /operators
[
    {
        \"op\": \"replace_endpointslices\",
        \"name\": \"service-a-epslice1\",
        \"namespace\": \"ns-a\",
        \"apiVersion\": \"discovery.k8s.io/v1\",
        \"kind\": \"EndpointSlice\",
        \"metadata\": {
            \"name\": \"service-a-epslice1\",
            \"labels\": {
                \"kubernetes.io/service-name\": \"service-a\"
            }
        },
        \"addressType\": \"IPv4\",
        \"endpoints\": [
            {
                \"addresses\": [
                    \"10.0.0.1\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node1\"
            },
            {
                \"addresses\": [
                    \"10.0.0.2\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node2\"
            }
        ],
        \"ports\": [
            {
                \"name\": \"p1\",
                \"port\": 5001
            }
        ]
    }
]",

"GET /queries
[
  \"first/ns-a/service-a:p1\"
]",

"POST /operators
[
    {
        \"op\": \"replace_endpointslices\",
        \"name\": \"service-a-epslice1\",
        \"namespace\": \"ns-a\",
        \"apiVersion\": \"discovery.k8s.io/v1\",
        \"kind\": \"EndpointSlice\",
        \"metadata\": {
            \"name\": \"service-a-epslice1\",
            \"labels\": {
                \"kubernetes.io/service-name\": \"service-a\"
            }
        },
        \"addressType\": \"IPv4\",
        \"endpoints\": [
            {
                \"addresses\": [
                    \"10.0.0.1\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node1\"
            },
            {
                \"addresses\": [
                    \"10.0.0.2\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node2\"
            },
            {
                \"addresses\": [
                    \"10.0.0.3\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node3\"
            }
        ],
        \"ports\": [
            {
                \"name\": \"p1\",
                \"port\": 5001
            }
        ]
    }
]",

"GET /queries
[
  \"first/ns-a/service-a:p1\"
]",

]
--- more_headers
Content-type: application/json
--- response_body eval
[
    "DONE\n",
    "{ 2 }\n",
    "DONE\n",
    "{ 3 }\n",
]



=== TEST 7: endpointSlice scale for single-k8s mode
--- yaml_config eval: $::single_yaml_config
--- request eval
[

"POST /operators
[
    {
        \"op\": \"replace_endpointslices\",
        \"name\": \"service-a-epslice1\",
        \"namespace\": \"ns-a\",
        \"apiVersion\": \"discovery.k8s.io/v1\",
        \"kind\": \"EndpointSlice\",
        \"metadata\": {
            \"name\": \"service-a-epslice1\",
            \"labels\": {
                \"kubernetes.io/service-name\": \"service-a\"
            }
        },
        \"addressType\": \"IPv4\",
        \"endpoints\": [
            {
                \"addresses\": [
                    \"10.0.0.1\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node1\"
            },
            {
                \"addresses\": [
                    \"10.0.0.2\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node2\"
            }
        ],
        \"ports\": [
            {
                \"name\": \"p1\",
                \"port\": 5001
            }
        ]
    }
]",

"GET /queries
[
  \"ns-a/service-a:p1\"
]",

"POST /operators
[
    {
        \"op\": \"replace_endpointslices\",
        \"name\": \"service-a-epslice1\",
        \"namespace\": \"ns-a\",
        \"apiVersion\": \"discovery.k8s.io/v1\",
        \"kind\": \"EndpointSlice\",
        \"metadata\": {
            \"name\": \"service-a-epslice1\",
            \"labels\": {
                \"kubernetes.io/service-name\": \"service-a\"
            }
        },
        \"addressType\": \"IPv4\",
        \"endpoints\": [
            {
                \"addresses\": [
                    \"10.0.0.1\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node1\"
            },
            {
                \"addresses\": [
                    \"10.0.0.2\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node2\"
            },
            {
                \"addresses\": [
                    \"10.0.0.3\"
                ],
                \"conditions\": {
                    \"ready\": true,
                    \"serving\": true,
                    \"terminating\": false
                },
                \"nodeName\": \"service-a-node3\"
            }
        ],
        \"ports\": [
            {
                \"name\": \"p1\",
                \"port\": 5001
            }
        ]
    }
]",

"GET /queries
[
  \"ns-a/service-a:p1\"
]",

]
--- more_headers
Content-type: application/json
--- response_body eval
[
    "DONE\n",
    "{ 2 }\n",
    "DONE\n",
    "{ 3 }\n",
]






