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
    # restarts cause the memory cache to be emptied, don't do this
    $ENV{TEST_NGINX_FORCE_RESTART_ON_TEST} = 0;
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
use_hup();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<'EOF');
apisix:
    proxy_mode: http&stream
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
    admin:
        admin_key:
            - name: admin
              key: edd1c9f034335f136f87ad84b625c8f1
              role: admin
EOF
    }

    $block->set_value("stream_enable", 1);

    if (!defined $block->config) {
        # shared by every block that doesn't set its own --- config, so that
        # only TEST 8 (which deliberately uses a different --- config)
        # triggers a reload -- keeping it constant here avoids surprising
        # every other block with an unwanted worker replacement mid-test
        $block->set_value("config", <<'EOF');
    location /stream_request {
        content_by_lua_block {
            local sock, err = ngx.socket.tcp()
            assert(sock, err)

            local ok, err = sock:connect("127.0.0.1", 1985)
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
            sock:close()
            if not data then
                ngx.say("receive stream response error: ", err)
                return
            end
            ngx.print(data)
        }
    }
EOF
    }

    if (!defined $block->no_error_log) {
        # a privileged agent process runs the same init_worker machinery as a
        # regular worker but has no worker ordinal (ngx.worker.id() is nil),
        # so make sure nothing here ever tries to concatenate that into a key.
        $block->set_value("no_error_log", "attempt to concatenate a nil value");
    }
});

run_tests();

__DATA__

=== TEST 1: no ?wait at all still returns 202 immediately (pre-existing behavior, unaffected)
--- log_level: debug
--- request
PUT /apisix/admin/configs
{"routes":[{"id":"r1","uri":"/r1","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"},"plugins":{"proxy-rewrite":{"uri":"/hello"}}}]}
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
X-Digest: w1
--- error_code: 202



=== TEST 2: ?wait=0 is the same as no ?wait (still an immediate 202)
--- log_level: debug
--- request
PUT /apisix/admin/configs?wait=0
{"routes":[{"id":"r1","uri":"/r1","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"},"plugins":{"proxy-rewrite":{"uri":"/hello"}}}],"routes_conf_version":2}
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
X-Digest: w2
--- error_code: 202



=== TEST 3: a real ?wait actually waits, returning 200 once every worker (http and stream) has applied it
--- log_level: debug
--- request
PUT /apisix/admin/configs?wait=3000
{"routes":[{"id":"r1","uri":"/r1","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"},"plugins":{"proxy-rewrite":{"uri":"/hello"}}}],"routes_conf_version":3}
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
X-Digest: w3
--- error_code: 200



=== TEST 4: the route is already live (no sleep needed, the 200 from TEST 3 already confirmed it)
--- log_level: debug
--- request
GET /r1
--- error_code: 200
--- response_body
hello world



=== TEST 5: resubmitting the same digest is still 204, doesn't go through the wait loop at all
--- log_level: debug
--- request
PUT /apisix/admin/configs?wait=3000
{"routes":[{"id":"r1","uri":"/r1","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"},"plugins":{"proxy-rewrite":{"uri":"/hello"}}}],"routes_conf_version":3}
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
X-Digest: w3
--- error_code: 204



=== TEST 6: ?wait covers the stream subsystem too (no more guessing a sleep, the 200 means the TCP route is already live)
--- pipelined_requests eval
[
    "PUT /apisix/admin/configs?wait=3000\n" . "{\"stream_routes\":[{\"modifiedIndex\":1,\"server_addr\":\"127.0.0.1\",\"server_port\":1985,\"id\":1,\"upstream\":{\"nodes\":{\"127.0.0.1:1995\":1},\"type\":\"roundrobin\"}}]}",
    "GET /stream_request"
]
--- more_headers eval
[
    "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1\n" . "X-Digest: w6",
    "",
]
--- error_code eval
[200, 200]
--- response_body eval
["", "hello world\n"]



=== TEST 7: setup route for TEST 8, independent of whatever earlier tests left in "routes"
--- log_level: debug
--- request
PUT /apisix/admin/configs?wait=3000
{"routes":[{"id":"r7","uri":"/r7","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"},"plugins":{"proxy-rewrite":{"uri":"/hello"}}}]}
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
X-Digest: w7
--- error_code: 200



=== TEST 8: config restored synchronously in init_worker survives a reload (no empty-config window)
--- config
    location /t8 {} # a different location forces this test's worker(s) to reload
--- log_level: debug
--- request
GET /r7
--- error_code: 200
--- response_body
hello world



=== TEST 9: ?wait doesn't hang on a resource type whose owning plugin is disabled (e.g. protos / grpc-transcode never get a config.new() instance)
--- yaml_config
plugins: # only one unrelated plugin, no grpc-transcode enabled
    - real-ip
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
    admin:
        admin_key:
            - name: admin
              key: edd1c9f034335f136f87ad84b625c8f1
              role: admin
--- config
    location /t9 {} # a different location, together with the yaml_config
                     # above, forces a reload so the new plugin list
                     # actually takes effect (yaml_config alone is a no-op
                     # unless --- config also changes)
--- log_level: debug
--- request
PUT /apisix/admin/configs?wait=3000
{"routes":[{"id":"r9","uri":"/r9","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"}}]}
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
X-Digest: w9
--- error_code: 200
