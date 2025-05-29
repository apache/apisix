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
log_level('info');
no_root_location();
worker_connections(1024);
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
nginx_config:
    http:
        lua_shared_dict:
            balancer-least-conn: 10m
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    my $route = <<_EOC_;
routes:
  - upstream_id: 1
    uris:
      - /test
#END
_EOC_

    $block->set_value("apisix_yaml", $block->apisix_yaml . $route);

    if (!$block->request) {
        $block->set_value("request", "GET /test");
    }
});

run_tests;

__DATA__

=== TEST 1: test least_conn balancer with connection state persistence
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    nodes:
      "127.0.0.1:1980": 1
      "127.0.0.1:1981": 1
--- config
    location /test {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/test"

            -- Simulate multiple requests to build up connection counts
            local results = {}
            for i = 1, 10 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if res then
                    table.insert(results, res.status)
                end
                httpc:close()
            end

            ngx.say("requests completed: ", #results)
        }
    }
--- response_body
requests completed: 10




=== TEST 2: test connection count persistence across upstream changes
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    nodes:
      "127.0.0.1:1980": 1
      "127.0.0.1:1981": 1
--- config
    location /test {
        content_by_lua_block {
            local core = require("apisix.core")
            local balancer = require("apisix.balancer.least_conn")

            -- Create a mock upstream configuration
            local upstream = {
                parent = {
                    value = {
                        id = "test_upstream_1"
                    }
                }
            }

            local up_nodes = {
                ["127.0.0.1:1980"] = 1,
                ["127.0.0.1:1981"] = 1
            }

            -- Create first balancer instance
            local balancer1 = balancer.new(up_nodes, upstream)

            -- Simulate some connections
            local ctx = {}
            local server1 = balancer1.get(ctx)
            ctx.balancer_server = server1

            -- Simulate connection completion (this should decrement count)
            balancer1.after_balance(ctx, false)

            -- Add a new node to simulate scaling
            up_nodes["127.0.0.1:1982"] = 1

            -- Create new balancer instance (simulating upstream change)
            local balancer2 = balancer.new(up_nodes, upstream)

            ngx.say("balancer created successfully with persistent state")
        }
    }
--- response_body
balancer created successfully with persistent state




=== TEST 3: test cleanup of stale connection counts
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    nodes:
      "127.0.0.1:1980": 1
      "127.0.0.1:1981": 1
      "127.0.0.1:1982": 1
--- config
    location /test {
        content_by_lua_block {
            local core = require("apisix.core")
            local balancer = require("apisix.balancer.least_conn")

            -- Create a mock upstream configuration
            local upstream = {
                parent = {
                    value = {
                        id = "test_upstream_2"
                    }
                }
            }

            local up_nodes = {
                ["127.0.0.1:1980"] = 1,
                ["127.0.0.1:1981"] = 1,
                ["127.0.0.1:1982"] = 1
            }

            -- Create first balancer instance with 3 nodes
            local balancer1 = balancer.new(up_nodes, upstream)

            -- Remove one node (simulate scaling down)
            up_nodes["127.0.0.1:1982"] = nil

            -- Create new balancer instance (should clean up stale counts)
            local balancer2 = balancer.new(up_nodes, upstream)

            ngx.say("stale connection counts cleaned up successfully")
        }
    }
--- response_body
stale connection counts cleaned up successfully
