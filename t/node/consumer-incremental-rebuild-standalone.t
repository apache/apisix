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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<'EOF_YAML');
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
    admin:
        admin_key:
            - name: admin
              key: edd1c9f034335f136f87ad84b625c8f1
              role: admin
EOF_YAML
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: consumers dropped by a config replacement stop authenticating right away
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("apisix.core").json
            local base = "http://127.0.0.1:" .. ngx.var.server_port

            local function consumer(name)
                return { username = name,
                         plugins = { ["key-auth"] = { key = "snap-" .. name } } }
            end

            local function put_config(consumers, digest)
                local httpc = http.new()
                local res, err = httpc:request_uri(base .. "/apisix/admin/configs", {
                    method = "PUT",
                    body = json.encode({
                        routes = {{
                            id = "r1",
                            uri = "/hello",
                            plugins = { ["key-auth"] = {} },
                            upstream = { nodes = { ["127.0.0.1:1980"] = 1 },
                                         type = "roundrobin" },
                        }},
                        consumers = consumers,
                    }),
                    headers = {
                        ["X-API-KEY"] = "edd1c9f034335f136f87ad84b625c8f1",
                        ["X-Digest"] = digest,
                        ["Content-Type"] = "application/json",
                    },
                })
                assert(res, err)
                assert(res.status == 202, "PUT /configs returned " .. res.status)
                ngx.sleep(1)
            end

            local function hit(name)
                local httpc = http.new()
                local res = assert(httpc:request_uri(base .. "/hello", {
                    headers = { apikey = "snap-" .. name },
                }))
                return res.status
            end

            put_config({ consumer("alice"), consumer("bob"), consumer("carol") }, "v1")
            ngx.say("alice: ", hit("alice"), ", bob: ", hit("bob"),
                    ", carol: ", hit("carol"))

            -- alice and carol go away, bob survives
            put_config({ consumer("bob") }, "v2")
            ngx.say("alice: ", hit("alice"), ", bob: ", hit("bob"),
                    ", carol: ", hit("carol"))
        }
    }
--- response_body
alice: 200, bob: 200, carol: 200
alice: 401, bob: 200, carol: 401
--- timeout: 10
