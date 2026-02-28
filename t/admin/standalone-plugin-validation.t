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
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<'_EOC_');
apisix:
    admin_key:
        - name: admin
          key: edd1c9f034335f136f87ad84b625c8f1
          role: admin
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_
    }

    $block->set_value("stream_enable", 1);
});

run_tests();

__DATA__

=== TEST 1: missing plugin on route blocks route matching
--- extra_yaml_config
plugins:
  - redirect
--- apisix_yaml
routes:
  - id: 1
    uri: /hello
    plugins:
      openid-connect:
        client_id: x
        client_secret: x
        discovery: x
        scope: openid email
        bearer_only: false
        realm: x
    upstream:
      type: roundrobin
      nodes:
        "127.0.0.1:1980": 1
#END
--- request
GET /hello
--- error_code: 404
--- error_log
unknown plugin [openid-connect]



=== TEST 2: missing plugin on stream route blocks stream matching
--- extra_yaml_config
stream_plugins:
  - ip-restriction
--- apisix_yaml
stream_routes:
  - id: 1
    server_port: 1985
    plugins:
      syslog:
        host: 127.0.0.1
        port: 514
    upstream:
      type: roundrobin
      nodes:
        "127.0.0.1:1995": 1
#END
--- config
location /stream_request {
    content_by_lua_block {
        ngx.sleep(1)  -- wait for the stream route to take effect

        local tcp_request = function(host, port)
            local sock, err = ngx.socket.tcp()
            assert(sock, err)

            local ok, err = sock:connect(host, port)
            if not ok then
                ngx.say("connect to stream server error: ", err)
                return
            end
            local bytes, err = sock:send("mmm")
            if not bytes then
                ngx.say("send stream request error: ", err)
                return
            end

            local data, err = sock:receive("*a")
            if not data then
                sock:close()
                ngx.say("receive stream response error: ", err)
                return
            end
            sock:close()
            ngx.print(data)
        end

        tcp_request("127.0.0.1", 1985)
    }
}
--- request
GET /stream_request
--- response_body
receive stream response error: connection reset by peer
--- error_log
unknown plugin [syslog]
