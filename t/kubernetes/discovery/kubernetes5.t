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
        ssl_verify: false
      client:
        token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"
      namespace_selector:
        equal: ns-a
    - id: second
      service:
        schema: "http"
        host: "127.0.0.1"
        port: "6445"
      client:
        token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"

_EOC_

    # no apiserver listens on 6446, so the tests below own the endpoint dicts
    our $offline_yaml_config = <<_EOC_;
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
        schema: "http"
        host: "127.0.0.1"
        port: "6446"
      client:
        token: "fake"
    - id: second
      service:
        schema: "http"
        host: "127.0.0.1"
        port: "6446"
      client:
        token: "fake"

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
              for _, query in ipairs(queries) do
                local args
                if query.cluster_ids then
                    args = {cluster_ids = query.cluster_ids}
                end
                local nodes = d.nodes(query.service_name, args)
                if nodes == nil or #nodes == 0 then
                    response_body = response_body .. " " .. 0
                else
                    response_body = response_body .. " " .. #nodes
                end
              end
              ngx.say(response_body .. " }")
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

                for _, op in ipairs(operators) do
                    local path = "/api/v1/namespaces/" .. op.namespace .. "/endpoints/" .. op.name
                    local body
                    if #op.subsets == 0 then
                        body = '[{"path":"/subsets","op":"replace","value":[]}]'
                    else
                        local t = { { op = "replace", path = "/subsets", value = op.subsets } }
                        body = core.json.encode(t, true)
                    end

                    local httpc = http.new()
                    local res, err = httpc:request_uri("http://127.0.0.1:6445" .. path, {
                        method = "PATCH",
                        headers = {
                            ["Host"] = "127.0.0.1:6445",
                            ["Content-Type"] = "application/json-patch+json",
                        },
                        body = body,
                    })
                    if not res then
                        core.log.error("operator k8s cluster error: ", err)
                        return 500
                    end
                    if res.status ~= 200 and res.status ~= 201 then
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

=== TEST 1: create endpoints
--- yaml_config eval: $::yaml_config
--- request
POST /operators
[
  {
    "namespace": "ns-a",
    "name": "ep",
    "subsets": [
      {
        "addresses": [{"ip": "10.0.1.1"}],
        "ports": [{"name": "p1", "port": 5001}]
      }
    ]
  },
  {
    "namespace": "ns-b",
    "name": "ep",
    "subsets": [
      {
        "addresses": [{"ip": "10.0.2.1"}, {"ip": "10.0.2.2"}],
        "ports": [{"name": "p1", "port": 5001}]
      }
    ]
  }
]
--- more_headers
Content-type: application/json
--- response_body
DONE



=== TEST 2: select clusters by cluster_ids
--- yaml_config eval: $::yaml_config
--- request
GET /queries
[
  {"service_name": "ns-a/ep:p1", "cluster_ids": ["first"]},
  {"service_name": "ns-a/ep:p1", "cluster_ids": ["second"]},
  {"service_name": "ns-a/ep:p1", "cluster_ids": ["first", "second"]},
  {"service_name": "ns-b/ep:p1", "cluster_ids": ["first"]},
  {"service_name": "ns-b/ep:p1", "cluster_ids": ["second"]},
  {"service_name": "ns-b/ep:p1", "cluster_ids": ["first", "second"]},
  {"service_name": "ns-b/ep:p1", "cluster_ids": ["third", "second"]},
  {"service_name": "ns-b/ep:p1", "cluster_ids": ["third"]},
  {"service_name": "first/ns-a/ep:p1"},
  {"service_name": "first/ns-b/ep:p1"},
  {"service_name": "second/ns-b/ep:p1"}
]
--- more_headers
Content-type: application/json
--- response_body
{ 1 1 1 0 2 2 2 0 1 0 2 }
--- error_log
skip unknown kubernetes discovery cluster ids: third, service: ns-b/ep:p1



=== TEST 3: endpoint changes in the selected clusters keep refreshing
--- yaml_config eval: $::yaml_config
--- request eval
[

"GET /queries
[
  {\"service_name\": \"ns-b/ep:p1\", \"cluster_ids\": [\"first\", \"second\"]}
]",

"POST /operators
[{\"name\":\"ep\",\"namespace\":\"ns-b\",\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.2.1\"},{\"ip\":\"10.0.2.2\"},{\"ip\":\"10.0.2.3\"}],\"ports\":[{\"name\":\"p1\",\"port\":5001}]}]}]",

"GET /queries
[
  {\"service_name\": \"ns-b/ep:p1\", \"cluster_ids\": [\"first\", \"second\"]}
]",

"POST /operators
[{\"name\":\"ep\",\"namespace\":\"ns-b\",\"subsets\":[]}]",

"GET /queries
[
  {\"service_name\": \"ns-b/ep:p1\", \"cluster_ids\": [\"first\", \"second\"]}
]"

]
--- response_body eval
[
    "{ 2 }\n",
    "DONE\n",
    "{ 3 }\n",
    "DONE\n",
    "{ 0 }\n",
]



=== TEST 4: union of the selected clusters
--- yaml_config eval: $::offline_yaml_config
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local function set_endpoints(id, key, endpoints, version)
                local dict = ngx.shared["kubernetes-" .. id]
                dict:set(key, core.json.encode(endpoints))
                dict:set(key .. "#version", version)
            end
            local d = require("apisix.discovery.kubernetes")

            local function show(service_name, cluster_ids)
                local nodes = d.nodes(service_name, {cluster_ids = cluster_ids})
                if not nodes then
                    ngx.say("nil")
                    return
                end
                local addrs = {}
                for _, node in ipairs(nodes) do
                    table.insert(addrs, node.host .. ":" .. node.port)
                end
                table.sort(addrs)
                ngx.say(table.concat(addrs, " "))
            end

            set_endpoints("first", "ns/svc", {p1 = {
                {host = "10.0.0.1", port = 80, weight = 50},
                {host = "10.0.0.9", port = 80, weight = 50},
            }}, "1")
            set_endpoints("second", "ns/svc", {p1 = {
                {host = "10.0.0.2", port = 80, weight = 50},
                {host = "10.0.0.9", port = 80, weight = 50},
            }}, "1")
            set_endpoints("first", "ns/only-first", {p1 = {
                {host = "10.0.1.1", port = 80, weight = 50},
            }}, "1")

            show("ns/svc:p1", {"first", "second"})
            show("ns/svc:p1", {"first"})
            show("ns/svc:p1", {"second"})
            show("ns/only-first:p1", {"second"})
            show("ns/only-first:p1", {"second", "first"})
            show("second/ns/svc:p1", {"second"})

            set_endpoints("second", "ns/svc", {p1 = {
                {host = "10.0.0.2", port = 80, weight = 50},
                {host = "10.0.0.3", port = 80, weight = 50},
            }}, "2")
            show("ns/svc:p1", {"first", "second"})
        }
    }
--- request
GET /t
--- response_body
10.0.0.1:80 10.0.0.2:80 10.0.0.9:80
10.0.0.1:80 10.0.0.9:80
10.0.0.2:80 10.0.0.9:80
nil
10.0.1.1:80
nil
10.0.0.1:80 10.0.0.2:80 10.0.0.3:80 10.0.0.9:80
--- error_log
service_name must be namespace/name:port_name when discovery_args.cluster_ids is set, got: second/ns/svc:p1
--- no_error_log
skip unknown kubernetes discovery cluster ids



=== TEST 5: proxy to the selected clusters only
--- yaml_config eval: $::offline_yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: ns/svc:p1
      discovery_type: kubernetes
      discovery_args:
        cluster_ids:
          - second
      type: roundrobin
  -
    uri: /hello1
    upstream:
      service_name: ns/svc:p1
      discovery_type: kubernetes
      discovery_args:
        cluster_ids:
          - third
          - fourth
      type: roundrobin
  -
    uri: /hello_chunked
    upstream:
      service_name: ns/only-second:p1
      discovery_type: kubernetes
      discovery_args:
        cluster_ids:
          - first
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local function set_endpoints(id, key, endpoints, version)
                local dict = ngx.shared["kubernetes-" .. id]
                dict:set(key, core.json.encode(endpoints))
                dict:set(key .. "#version", version)
            end
            local http = require("resty.http")

            set_endpoints("first", "ns/svc", {p1 = {
                {host = "127.0.0.1", port = 1979, weight = 50},
            }}, "1")
            set_endpoints("second", "ns/svc", {p1 = {
                {host = "127.0.0.1", port = 1980, weight = 50},
            }}, "1")
            set_endpoints("second", "ns/only-second", {p1 = {
                {host = "127.0.0.1", port = 1980, weight = 50},
            }}, "1")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            for _, path in ipairs({"/hello", "/hello", "/hello", "/hello1", "/hello_chunked"}) do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri .. path)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.say(path, " ", res.status)
            end
        }
    }
--- request
GET /t
--- response_body
/hello 200
/hello 200
/hello 200
/hello1 503
/hello_chunked 503
--- error_log
skip unknown kubernetes discovery cluster ids: third, fourth, service: ns/svc:p1



=== TEST 6: cluster_ids requires multiple clusters
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
      host: "127.0.0.1"
      port: "6446"
    client:
      token: "fake"
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local d = require("apisix.discovery.kubernetes")

            local dict = ngx.shared["kubernetes"]
            dict:set("ns/svc", core.json.encode({p1 = {
                {host = "10.0.0.1", port = 80, weight = 50},
            }}))
            dict:set("ns/svc#version", "1")

            local nodes = d.nodes("ns/svc:p1")
            ngx.say(#nodes)
            nodes = d.nodes("ns/svc:p1", {cluster_ids = {"first"}})
            ngx.say(tostring(nodes))
        }
    }
--- request
GET /t
--- response_body
1
nil
--- error_log
discovery_args.cluster_ids requires kubernetes discovery configured with multiple clusters



=== TEST 7: the data plane rejects a cluster id prefix but not an unknown id
--- yaml_config eval: $::offline_yaml_config
--- apisix_yaml
upstreams:
  -
    id: 1
    service_name: second/ns/svc:p1
    discovery_type: kubernetes
    discovery_args:
      cluster_ids:
        - second
    type: roundrobin
  -
    id: 2
    service_name: ns/svc:p1
    discovery_type: kubernetes
    discovery_args:
      cluster_ids:
        - second
        - third
    type: roundrobin
routes:
  -
    uri: /hello
    upstream_id: 1
  -
    uri: /hello1
    upstream_id: 2
#END
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local http = require("resty.http")

            local dict = ngx.shared["kubernetes-second"]
            dict:set("ns/svc", core.json.encode({p1 = {
                {host = "127.0.0.1", port = 1980, weight = 50},
            }}))
            dict:set("ns/svc#version", "1")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            for _, path in ipairs({"/hello", "/hello1"}) do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri .. path)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.say(path, " ", res.status)
            end
        }
    }
--- request
GET /t
--- response_body
/hello 502
/hello1 200
--- error_log
service_name must be namespace/name:port_name when discovery_args.cluster_ids is set, got: second/ns/svc:p1
skip unknown kubernetes discovery cluster ids: third, service: ns/svc:p1



=== TEST 8: stream route with cluster_ids
--- yaml_config eval: $::offline_yaml_config
--- apisix_yaml
stream_routes:
  -
    id: 1
    server_addr: 127.0.0.1
    server_port: 1985
    upstream:
      service_name: ns/svc:p1
      discovery_type: kubernetes
      discovery_args:
        cluster_ids:
          - second
      type: roundrobin
#END
--- stream_extra_init_worker_by_lua
    local core = require("apisix.core")
    local d = require("apisix.discovery.kubernetes")

    local function set_endpoints(id, key, endpoints, version)
        local dict = ngx.shared["kubernetes-" .. id .. "-stream"]
        dict:set(key, core.json.encode(endpoints))
        dict:set(key .. "#version", version)
    end

    set_endpoints("first", "ns/svc", {p1 = {
        {host = "127.0.0.1", port = 1979, weight = 50},
        {host = "127.0.0.1", port = 1995, weight = 50},
    }}, "1")
    set_endpoints("second", "ns/svc", {p1 = {
        {host = "127.0.0.1", port = 1995, weight = 50},
        {host = "127.0.0.2", port = 1995, weight = 50},
    }}, "1")

    local nodes = d.nodes("ns/svc:p1", {cluster_ids = {"first", "second"}})
    local addrs = {}
    for _, node in ipairs(nodes) do
        table.insert(addrs, node.host .. ":" .. node.port)
    end
    table.sort(addrs)
    core.log.warn("stream nodes of first and second: ", table.concat(addrs, " "))
--- stream_request
m
--- stream_response
hello world
--- error_log
stream nodes of first and second: 127.0.0.1:1979 127.0.0.1:1995 127.0.0.2:1995
--- no_error_log
skip unknown kubernetes discovery cluster ids
