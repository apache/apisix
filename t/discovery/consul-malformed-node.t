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
no_shuffle();


add_block_preprocessor(sub {
    my ($block) = @_;

    # mock consul server: /v1/health/service/service_a returns one malformed
    # entry (without the Service field) followed by two valid entries
    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 18506;

        location /v1/catalog/services {
            content_by_lua_block {
                ngx.header["X-Consul-Index"] = "1"
                ngx.header.content_type = "application/json"
                ngx.say('{"service_a":[]}')
            }
        }

        location /v1/health/state/any {
            content_by_lua_block {
                ngx.header["X-Consul-Index"] = "1"
                ngx.header.content_type = "application/json"
                ngx.say('[]')
            }
        }

        location /v1/health/service/service_a {
            content_by_lua_block {
                ngx.header["X-Consul-Index"] = "1"
                ngx.header.content_type = "application/json"
                ngx.say('['
                    .. '{"Node":{"Node":"reclaimed-node","Address":"127.0.0.1"},"Checks":[]},'
                    .. '{"Node":{"Node":"node1","Address":"127.0.0.1"},'
                    .. '"Service":{"ID":"service_a1","Service":"service_a",'
                    .. '"Address":"127.0.0.1","Port":30511},"Checks":[]},'
                    .. '{"Node":{"Node":"node2","Address":"127.0.0.1"},'
                    .. '"Service":{"ID":"service_a2","Service":"service_a",'
                    .. '"Address":"127.0.0.1","Port":30512},"Checks":[]}'
                    .. ']')
            }
        }
    }

    server {
        listen 30511;

        location /hello {
            content_by_lua_block {
                ngx.say("server 1")
            }
        }
    }
    server {
        listen 30512;

        location /hello {
            content_by_lua_block {
                ngx.say("server 2")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  consul:
    servers:
      - "http://127.0.0.1:18506"
    timeout:
      connect: 1000
      read: 1000
      wait: 60
    weight: 1
    fetch_interval: 1
    keepalive: true
_EOC_

run_tests();

__DATA__

=== TEST 1: one malformed health service entry should not discard the remaining valid nodes
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: service_a
      discovery_type: consul
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(2)

            local http = require("resty.http")
            local bodies = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
                if not res then
                    ngx.say("request failed: ", err)
                    return
                end
                if res.status ~= 200 then
                    ngx.say("unexpected status: ", res.status)
                    return
                end
                table.insert(bodies, res.body)
            end
            table.sort(bodies)
            ngx.print(table.concat(bodies))
        }
    }
--- timeout: 5
--- request
GET /t
--- response_body
server 1
server 2
--- error_log
invalid consul service entry without Service field
