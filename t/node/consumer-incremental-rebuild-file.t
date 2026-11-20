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
    my $format = $block->file_format;
    $block->set_value("apisix_$format", $format eq 'yaml' ? "{}\n#END" : "{}");
    $block->set_value("request", "GET /t");
    $block->set_value("config", <<'LUA');
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local http = require("resty.http")
            local profile = require("apisix.core.profile")
            local format = require("apisix.core.config_yaml").file_type
            local path = profile:yaml_path("apisix")
            if format == "json" then
                path = path:sub(1, -5) .. "json"
            end
            local suffix = format == "yaml" and "\n#END\n" or ""
            local conf = {
                routes = {{
                    id = "snapshot",
                    uri = "/snapshot",
                    plugins = {
                        ["key-auth"] = {},
                        ["proxy-rewrite"] = { uri = "/hello" },
                    },
                    upstream = { nodes = { ["127.0.0.1:1980"] = 1 },
                                 type = "roundrobin" },
                }},
                consumers = {
                    { username = "alice",
                      plugins = { ["key-auth"] = { key = "file-alice" } } },
                    { username = "bob",
                      plugins = { ["key-auth"] = { key = "file-bob" } } },
                },
            }
            local function replace()
                -- JSON is valid YAML too; only YAML needs the end marker.
                local f = assert(io.open(path .. ".new", "w"))
                assert(f:write(core.json.encode(conf), suffix))
                assert(f:close())
                assert(os.rename(path .. ".new", path))
            end
            local function hit(key)
                local res = assert(http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/snapshot",
                    { headers = { apikey = key } }))
                return res.status
            end
            local function wait_version(previous)
                local consumer = require("apisix.consumer")
                for _ = 1, 100 do
                    local _, version = consumer.consumers()
                    if version ~= previous then
                        return version
                    end
                    ngx.sleep(0.05)
                end
                error("configuration did not reload")
            end
            local consumer = require("apisix.consumer")
            local _, version = consumer.consumers()
            -- File mtime has one-second resolution.
            ngx.sleep(1.1)
            replace()
            version = wait_version(version)
            -- Routes and consumers have separate sync timers.
            for _ = 1, 100 do
                if hit("file-bob") == 200 then
                    break
                end
                ngx.sleep(0.05)
            end
            ngx.say("initial: ", hit("file-alice"), ", ", hit("file-bob"))

            ngx.sleep(1.1)
            conf.consumers = { conf.consumers[2] }
            replace()
            version = wait_version(version)
            ngx.say("after removal: ", hit("file-alice"), ", ", hit("file-bob"))

            ngx.sleep(1.1)
            conf.consumers = nil
            replace()
            wait_version(version)
            ngx.say("after clearing: ", hit("file-alice"), ", ", hit("file-bob"))
        }
    }
LUA
    $block->set_value("response_body", <<'BODY');
initial: 200, 200
after removal: 401, 200
after clearing: 401, 401
BODY
});

run_tests();

__DATA__

=== TEST 1: YAML file reload revokes removed consumers before the next lookup
--- file_format: yaml
--- timeout: 20



=== TEST 2: JSON file reload revokes removed consumers before the next lookup
--- file_format: json
--- timeout: 20
