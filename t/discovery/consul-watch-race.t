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

    # mock consul server: both indexes change together every 3 seconds. The
    # catalog watch answers 0.3s after a change while the health watch streams a
    # large chunked body for about a second, and a non-blocking catalog read
    # takes 1.5s, so the health body is still being read when the catalog watch
    # returns and finishes while the following fetch is waiting for its response.
    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 18507;

        location /v1/catalog/services {
            content_by_lua_block {
                local index = math.floor(ngx.now() / 3)
                local requested = tonumber(ngx.req.get_uri_args().index)
                if requested then
                    local deadline = ngx.now() + 60
                    while index <= requested and ngx.now() < deadline do
                        ngx.sleep(0.05)
                        index = math.floor(ngx.now() / 3)
                    end
                    ngx.sleep(0.3)
                else
                    ngx.sleep(1.5)
                end
                ngx.header["X-Consul-Index"] = index
                ngx.header.content_type = "application/json"
                ngx.say('{"consul":[],"service_a":[]}')
            }
        }

        location /v1/health/state/any {
            content_by_lua_block {
                local index = math.floor(ngx.now() / 3)
                local requested = tonumber(ngx.req.get_uri_args().index)
                ngx.header.content_type = "application/json"
                if not requested then
                    ngx.header["X-Consul-Index"] = index
                    ngx.say('[]')
                    return
                end

                local deadline = ngx.now() + 60
                while index <= requested and ngx.now() < deadline do
                    ngx.sleep(0.05)
                    index = math.floor(ngx.now() / 3)
                end
                ngx.header["X-Consul-Index"] = index
                local check = '{"Node":"node1","CheckID":"check","Status":"passing",'
                              .. '"Notes":"' .. string.rep("x", 2000) .. '"},'
                ngx.print("[")
                for _ = 1, 100 do
                    ngx.print(check)
                    ngx.flush(true)
                    ngx.sleep(0.01)
                end
                ngx.print('{"Node":"node1","CheckID":"last","Status":"passing"}]')
            }
        }

        location /v1/health/service/service_a {
            content_by_lua_block {
                ngx.header["X-Consul-Index"] = math.floor(ngx.now() / 3)
                ngx.header.content_type = "application/json"
                ngx.say('[{"Node":{"Node":"node1","Address":"127.0.0.1"},'
                    .. '"Service":{"ID":"service_a1","Service":"service_a",'
                    .. '"Address":"127.0.0.1","Port":30511},"Checks":[]}]')
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
      - "http://127.0.0.1:18507"
    timeout:
      connect: 1000
      read: 3000
      wait: 60
    keepalive: true
_EOC_

run_tests();

__DATA__

=== TEST 1: a watcher still reading its response body must not break the following fetch
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
            ngx.sleep(6)

            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.status = res.status
            ngx.print(res.body)
        }
    }
--- timeout: 10
--- request
GET /t
--- response_body
server 1
--- no_error_log
[error]
got boolean
