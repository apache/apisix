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
no_shuffle();
no_root_location();
log_level("warn");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    # no apiserver listens on 6446, the tests only check the Admin API
    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
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

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: validate cluster_ids in the Admin API
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local cases = {
                {service_name = "ns/svc:p1", discovery_args = {cluster_ids = {"first"}}},
                {service_name = "ns/svc:p1", discovery_args = {cluster_ids = {"second", "first"}}},
                {service_name = "ns/svc:p1",
                 discovery_args = {cluster_ids = {"third", "first", "fourth"}}},
                {service_name = "first/ns/svc:p1", discovery_args = {cluster_ids = {"first"}}},
                {service_name = "ns/svc:p1", discovery_args = {cluster_ids = {}}},
                {service_name = "ns/svc:p1", discovery_args = {cluster_ids = {"first", "first"}}},
                {service_name = "ns/svc:p1", discovery_args = {cluster_ids = {1}}},
                {service_name = "ns/svc:p1", discovery_args = {cluster_ids = "first"}},
                {service_name = "first/ns/svc:p1"},
                {service_name = "svc:p1", discovery_args = {cluster_ids = {"first"}}},
                {service_name = "/svc:p1", discovery_args = {cluster_ids = {"first"}}},
                {service_name = "ns/:p1", discovery_args = {cluster_ids = {"first"}}},
                {service_name = "ns/svc:", discovery_args = {cluster_ids = {"first"}}},
                {service_name = "ns/svc", discovery_args = {cluster_ids = {"first"}}},
            }
            for _, case in ipairs(cases) do
                case.discovery_type = "kubernetes"
                case.type = "roundrobin"
                local code, body = t('/apisix/admin/upstreams/1', ngx.HTTP_PUT, case)
                if code >= 300 then
                    ngx.say(code, " ", (body:gsub("%s+$", "")))
                else
                    ngx.say("passed")
                end
            end
        }
    }
--- response_body
passed
passed
400 {"error_msg":"unknown kubernetes discovery cluster ids in discovery_args.cluster_ids: third, fourth"}
400 {"error_msg":"service_name must be namespace/name:port_name when discovery_args.cluster_ids is set, got: first/ns/svc:p1"}
400 {"error_msg":"invalid configuration: property \"discovery_args\" validation failed: property \"cluster_ids\" validation failed: expect array to have at least 1 items"}
400 {"error_msg":"invalid configuration: property \"discovery_args\" validation failed: property \"cluster_ids\" validation failed: expected unique items but items 1 and 2 are equal"}
400 {"error_msg":"invalid configuration: property \"discovery_args\" validation failed: property \"cluster_ids\" validation failed: failed to validate item 1: wrong type: expected string, got number"}
400 {"error_msg":"invalid configuration: property \"discovery_args\" validation failed: property \"cluster_ids\" validation failed: wrong type: expected array, got string"}
passed
400 {"error_msg":"service_name must be namespace/name:port_name when discovery_args.cluster_ids is set, got: svc:p1"}
400 {"error_msg":"service_name must be namespace/name:port_name when discovery_args.cluster_ids is set, got: /svc:p1"}
400 {"error_msg":"service_name must be namespace/name:port_name when discovery_args.cluster_ids is set, got: ns/:p1"}
400 {"error_msg":"service_name must be namespace/name:port_name when discovery_args.cluster_ids is set, got: ns/svc:"}
400 {"error_msg":"service_name must be namespace/name:port_name when discovery_args.cluster_ids is set, got: ns/svc"}



=== TEST 2: validate cluster_ids in an inline upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, uri in ipairs({"/apisix/admin/routes/1", "/apisix/admin/services/1"}) do
                local conf = {
                    upstream = {
                        type = "roundrobin",
                        discovery_type = "kubernetes",
                        service_name = "ns/svc:p1",
                        discovery_args = {cluster_ids = {"first", "third"}},
                    },
                }
                if uri == "/apisix/admin/routes/1" then
                    conf.uri = "/hello"
                end
                local code, body = t(uri, ngx.HTTP_PUT, conf)
                ngx.say(code, " ", (body:gsub("%s+$", "")))
            end
        }
    }
--- response_body
400 {"error_msg":"unknown kubernetes discovery cluster ids in discovery_args.cluster_ids: third"}
400 {"error_msg":"unknown kubernetes discovery cluster ids in discovery_args.cluster_ids: third"}



=== TEST 3: cluster_ids of another discovery type is not checked by kubernetes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1', ngx.HTTP_PUT, {
                type = "roundrobin",
                discovery_type = "consul",
                service_name = "first/ns/svc:p1",
                discovery_args = {cluster_ids = {"third"}},
            })
            ngx.say(code < 300 and "passed" or body)
        }
    }
--- response_body
passed



=== TEST 4: cluster_ids requires multiple clusters
--- extra_yaml_config
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
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1', ngx.HTTP_PUT, {
                type = "roundrobin",
                discovery_type = "kubernetes",
                service_name = "ns/svc:p1",
                discovery_args = {cluster_ids = {"first"}},
            })
            ngx.say(code, " ", (body:gsub("%s+$", "")))
        }
    }
--- response_body
400 {"error_msg":"discovery_args.cluster_ids requires kubernetes discovery configured with multiple clusters"}
