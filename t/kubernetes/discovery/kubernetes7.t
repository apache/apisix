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

# no apiserver listens on 6446, so the tests below own the endpoint dict
BEGIN {
    our $offline_yaml_config = <<_EOC_;
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
_EOC_
}

use t::APISIX 'no_plan';

repeat_each(1);
log_level('warn');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $apisix_yaml = $block->apisix_yaml // <<_EOC_;
routes: []
#END
_EOC_

    $block->set_value("apisix_yaml", $apisix_yaml);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: a worker re-reads the shared dict once its cache entry expires (#14149)
# The dict holds one key per service and is the source of truth; there is no
# version key a worker could observe before the content.
--- yaml_config eval: $::offline_yaml_config
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local d = require("apisix.discovery.kubernetes")
            local dict = ngx.shared["kubernetes"]

            local function publish(ip)
                dict:set("ns/svc", core.json.encode({p1 = {
                    {host = ip, port = 80, weight = 50},
                }}))
            end
            local function first_host()
                local nodes = d.nodes("ns/svc:p1")
                return nodes and nodes[1].host or "nil"
            end

            publish("10.0.0.1")
            ngx.say(first_host())
            publish("10.0.0.2")
            ngx.say(first_host())
            ngx.sleep(1.2)
            ngx.say(first_host())
        }
    }
--- response_body
10.0.0.1
10.0.0.1
10.0.0.2
--- error_log
connect apiserver failed



=== TEST 2: the writer publishes exactly one key per service
--- yaml_config eval: $::offline_yaml_config
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")
            local real_dict = ngx.shared["kubernetes"]

            -- record every write that reaches the shared dict
            local writing = {set = true, safe_set = true, add = true,
                             safe_add = true, replace = true}
            local writes = {}
            local recording_dict = setmetatable({}, {
                __index = function(_, method)
                    return function(_, key, ...)
                        if writing[method] then
                            table.insert(writes, method .. " " .. key)
                        end
                        return real_dict[method](real_dict, key, ...)
                    end
                end,
            })

            local ok, err = k8s_core.update_endpoint_dict(
                {endpoint_dict = recording_dict},
                {p1 = {{host = "10.0.0.1", port = 80, weight = 50}}},
                "ns/svc2")
            ngx.say(ok, " ", err or "", " ", table.concat(writes, ","))
        }
    }
--- response_body
true  safe_set ns/svc2
--- error_log
connect apiserver failed
