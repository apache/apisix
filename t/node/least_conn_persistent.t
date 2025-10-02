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
log_level('debug');
no_root_location();
worker_connections(1024);
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    # Add http_config to include shared dict for connection counting
    my $http_config = <<_EOC_;
        lua_shared_dict balancer-least-conn 10m;
_EOC_

    $block->set_value("http_config", $http_config);

    my $route = <<_EOC_;
routes:
  - upstream_id: 1
    uris:
      - /mysleep
#END
_EOC_

    $block->set_value("apisix_yaml", ($block->apisix_yaml || "") . $route);

    if (!$block->request) {
        $block->set_value("request", "GET /mysleep?seconds=0.1");
    }
});

run_tests();

__DATA__

=== TEST 1: test connection counting with persistent shared dict
--- apisix_yaml
upstreams:
  - id: 1
    type: least_conn
    nodes:
        "127.0.0.1:1980": 3
        "0.0.0.0:1980": 2
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/mysleep?seconds=0.1"

            local t = {}
            for i = 1, 3 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri..i, {method = "GET"})
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1980 while connecting to upstream
proxy request to 127.0.0.1:1980 while connecting to upstream
proxy request to 0.0.0.0:1980 while connecting to upstream



=== TEST 2: verify shared dict availability and connection counting
--- config
    location /t {
        content_by_lua_block {
            -- Check if shared dict is available
            local dict = ngx.shared["balancer-least-conn"]
            if dict then
                ngx.say("shared dict available: true")
                ngx.say("shared dict capacity: ", dict:capacity())
            else
                ngx.say("shared dict available: false")
                return
            end

            -- Test balancer creation with connection counting
            local least_conn = require("apisix.balancer.least_conn")
            local upstream = {
                id = "test_conn_counting",
                type = "least_conn"
            }
            local nodes = {
                ["10.1.1.1:8080"] = 1,
                ["10.1.1.2:8080"] = 1
            }

            -- Clean any existing data
            least_conn.cleanup_all()

            -- Create balancer
            local balancer = least_conn.new(nodes, upstream)
            if balancer then
                ngx.say("balancer with connection counting created: true")

                -- Simulate connections
                for i = 1, 4 do
                    local ctx = {}
                    local server = balancer.get(ctx)
                    ngx.say("connection ", i, " assigned to a server")
                end

                -- Check connection counts in shared dict
                local count1 = dict:get("conn_count:test_conn_counting:10.1.1.1:8080") or 0
                local count2 = dict:get("conn_count:test_conn_counting:10.1.1.2:8080") or 0
                ngx.say("final connection counts - server1: ", count1, ", server2: ", count2)

                -- Total connections should be 4
                local total_connections = count1 + count2
                ngx.say("total connections tracked: ", total_connections)
                ngx.say("connection counting working: ", total_connections == 4)
                ngx.say("connection distribution balanced: ", count1 == 2 and count2 == 2)

                -- Cleanup
                least_conn.cleanup_all()
            else
                ngx.say("balancer with connection counting created: false")
            end
        }
    }
--- request
GET /t
--- response_body
shared dict available: true
shared dict capacity: 10485760
balancer with connection counting created: true
connection 1 assigned to a server
connection 2 assigned to a server
connection 3 assigned to a server
connection 4 assigned to a server
final connection counts - server1: 2, server2: 2
total connections tracked: 4
connection counting working: true
connection distribution balanced: true



=== TEST 3: verify cleanup function exists and works
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")

            if type(least_conn.cleanup_all) == "function" then
                ngx.say("cleanup function exists: true")
                -- Call cleanup function to test it works
                least_conn.cleanup_all()
                ngx.say("cleanup function executed: true")
            else
                ngx.say("cleanup function exists: false")
            end
        }
    }
--- request
GET /t
--- response_body
cleanup function exists: true
cleanup function executed: true



=== TEST 4: demonstrate connection counting with weighted nodes
--- config
    location /t {
        content_by_lua_block {
            local least_conn = require("apisix.balancer.least_conn")
            local dict = ngx.shared["balancer-least-conn"]

            local upstream = {
                id = "test_weighted_counting",
                type = "least_conn"
            }

            -- Test with different weights: server1 weight=3, server2 weight=1
            local nodes = {
                ["172.16.1.1:9000"] = 3,  -- higher weight
                ["172.16.1.2:9000"] = 1   -- lower weight
            }

            -- Clean previous data
            least_conn.cleanup_all()

            -- Create balancer
            local balancer = least_conn.new(nodes, upstream)

            -- Make several connections
            ngx.say("making connections to test weighted least connection:")
            for i = 1, 6 do
                local ctx = {}
                local server = balancer.get(ctx)
                ngx.say("connection ", i, " -> ", server)
            end

            -- Check final connection counts
            local count1 = dict:get("conn_count:test_weighted_counting:172.16.1.1:9000") or 0
            local count2 = dict:get("conn_count:test_weighted_counting:172.16.1.2:9000") or 0

            ngx.say("final connection counts:")
            ngx.say("server1 (weight=3): ", count1, " connections")
            ngx.say("server2 (weight=1): ", count2, " connections")

            -- Higher weight server should get more connections
            ngx.say("higher weight server got more connections: ", count1 > count2)

            -- Cleanup
            least_conn.cleanup_all()
        }
    }
--- request
GET /t
--- response_body
making connections to test weighted least connection:
connection 1 -> 172.16.1.1:9000
connection 2 -> 172.16.1.1:9000
connection 3 -> 172.16.1.1:9000
connection 4 -> 172.16.1.1:9000
connection 5 -> 172.16.1.2:9000
connection 6 -> 172.16.1.2:9000
final connection counts:
server1 (weight=3): 4 connections
server2 (weight=1): 2 connections
higher weight server got more connections: true
