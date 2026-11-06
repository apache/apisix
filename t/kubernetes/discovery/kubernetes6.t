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

# End-to-end checks for the kubernetes discovery cache (apache/apisix#14149):
# the Endpoints object is changed through the real apiserver (kubectl proxy
# on 6445) and real requests are sent through APISIX to the fake backend on
# 1980/1981, so every worker's cache is exercised, not just the shared dict.

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
    service:
      host: "127.0.0.1"
      port: "6443"
      ssl_verify: false
    client:
      token_file: "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token"
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
routes:
  -
    uri: /server_port
    upstream:
      service_name: ns-a/ep:p1
      discovery_type: kubernetes
      type: roundrobin
  -
    uri: /hello
    upstream:
      service_name: ns-a/no-such-ep:p1
      discovery_type: kubernetes
      type: roundrobin
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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->timeout) {
        $block->set_value("timeout", "60");
    }
});

run_tests();

__DATA__

=== TEST 1: a Service published through the apiserver is served by every worker
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.k8s_discovery_e2e").new(ngx.var.server_port)

            ngx.say("patch: ", t.set_subsets(t.port_subsets(1980)))
            ngx.say("serving 1980 within 5s: ", t.wait_for("1980", 5, 5) ~= nil)
            ngx.say("answers not from 1980 in 40 requests: ", t.count_other_than("1980", 40))
        }
    }
--- response_body
patch: 200
serving 1980 within 5s: true
answers not from 1980 in 40 requests: 0



=== TEST 2: a change of the Endpoints reaches every worker within the cache ttl
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.k8s_discovery_e2e").new(ngx.var.server_port)

            t.set_subsets(t.port_subsets(1980))
            ngx.say("serving 1980 within 5s: ", t.wait_for("1980", 5, 5) ~= nil)

            ngx.say("patch: ", t.set_subsets(t.port_subsets(1981)))
            local elapsed, unexpected = t.wait_for("1981", 5, 5, {["1980"] = true, ["1981"] = true})
            ngx.say("switched to 1981 within 5s: ", elapsed ~= nil)
            ngx.say("answers that were neither 1980 nor 1981 during the switch: ", unexpected)
            ngx.say("answers not from 1981 in 40 requests: ", t.count_other_than("1981", 40))
        }
    }
--- response_body
serving 1980 within 5s: true
patch: 200
switched to 1981 within 5s: true
answers that were neither 1980 nor 1981 during the switch: 0
answers not from 1981 in 40 requests: 0



=== TEST 3: scaling the Endpoints to zero and back
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.k8s_discovery_e2e").new(ngx.var.server_port)

            t.set_subsets(t.port_subsets(1980))
            ngx.say("serving 1980 within 5s: ", t.wait_for("1980", 5, 5) ~= nil)

            ngx.say("patch to empty: ", t.set_subsets({}))
            ngx.say("503 within 5s: ", t.wait_for("503", 5, 5) ~= nil)

            ngx.say("patch back: ", t.set_subsets(t.port_subsets(1980)))
            ngx.say("serving 1980 again within 5s: ", t.wait_for("1980", 5, 5) ~= nil)
        }
    }
--- response_body
serving 1980 within 5s: true
patch to empty: 200
503 within 5s: true
patch back: 200
serving 1980 again within 5s: true



=== TEST 4: deleting and recreating the Endpoints object
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.k8s_discovery_e2e").new(ngx.var.server_port)

            t.set_subsets(t.port_subsets(1980))
            ngx.say("serving 1980 within 5s: ", t.wait_for("1980", 5, 5) ~= nil)

            ngx.say("delete: ", t.delete_endpoints())
            ngx.say("503 within 5s: ", t.wait_for("503", 5, 5) ~= nil)

            ngx.say("create: ", t.create_endpoints(t.port_subsets(1980)))
            ngx.say("serving 1980 again within 5s: ", t.wait_for("1980", 5, 5) ~= nil)
        }
    }
--- response_body
serving 1980 within 5s: true
delete: 200
503 within 5s: true
create: 201
serving 1980 again within 5s: true



=== TEST 5: unknown service, dump without version keys, fixture restored
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.k8s_discovery_e2e").new(ngx.var.server_port)

            t.set_subsets(t.port_subsets(1980))
            ngx.say("serving 1980 within 5s: ", t.wait_for("1980", 5, 5) ~= nil)

            ngx.say("unknown service: ", t.get("/hello"))

            local names = t.dump_names()
            ngx.say("dump has ns-a/ep: ", names["ns-a/ep"] == true)
            local version_keys = 0
            for name in pairs(names) do
                if name:find("#version", 1, true) then
                    version_keys = version_keys + 1
                end
            end
            ngx.say("dump version keys: ", version_keys)

            ngx.say("restore fixture: ", t.set_subsets(t.fixture_subsets()))
        }
    }
--- response_body
serving 1980 within 5s: true
unknown service: 503
dump has ns-a/ep: true
dump version keys: 0
restore fixture: 200
