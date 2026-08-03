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

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    if (!defined $block->stream_conf_enable) {
        $block->set_value("stream_enable", 1);

        if (!$block->stream_request) {
            $block->set_value("stream_request", "mmm");
        }
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream:
      nodes:
        "127.0.0.1:1995": 1
      type: roundrobin
#END
--- stream_response
hello world



=== TEST 2: rule with bad plugin
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    plugins:
        mqtt-proxy:
            uri: 1
    upstream:
      nodes:
        "127.0.0.1:1995": 1
      type: roundrobin
#END
--- error_log eval
qr/property "\w+" is required/



=== TEST 3: ignore unknown plugin
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    plugins:
        x-rewrite:
            uri: 1
    upstream:
      nodes:
        "127.0.0.1:1995": 1
      type: roundrobin
#END
--- error_log
err:unknown plugin [x-rewrite]



=== TEST 4: sanity with plugin
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    upstream_id: 1
    plugins:
      mqtt-proxy:
        protocol_name: "MQTT"
        protocol_level: 4
upstreams:
  - nodes:
      "127.0.0.1:1995": 1
    type: roundrobin
    id: 1
#END
--- stream_request eval
"\x10\x0f\x00\x04\x4d\x51\x54\x54\x04\x02\x00\x3c\x00\x03\x66\x6f\x6f"
--- stream_response
hello world



=== TEST 5: xRPC protocol works when stream_proxy is enabled and Admin API is disabled
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
    stream_proxy:
        tcp:
            - 9100
xrpc:
    protocols:
        - name: pingpong
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
stream_routes:
  - server_addr: 127.0.0.1
    server_port: 1985
    id: 1
    protocol:
      name: pingpong
    upstream:
      nodes:
        "127.0.0.1:1995": 1
      type: roundrobin
#END
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            ngx.req.read_body()
            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(503)
            end

            local bytes, err = sock:send(ngx.req.get_body_data())
            if not bytes then
                ngx.log(ngx.ERR, "send stream request error: ", err)
                return ngx.exit(503)
            end
            while true do
                local data, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
                ngx.print(data)
            end
        }
    }
--- stream_upstream_code
            local sock = ngx.req.socket(true)
            sock:settimeout(10)
            while true do
                local data = sock:receiveany(4096)
                if not data then
                    return
                end
                sock:send(data)
            end
--- request eval
"POST /t
pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- response_body eval
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- no_error_log
unknown protocol
[error]
[alert]
