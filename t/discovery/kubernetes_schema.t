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

repeat_each(2);
no_long_string();
no_root_location();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: id field validation
--- config
    location /t {
        content_by_lua_block {
            local k8s_schema = require("apisix.discovery.kubernetes.schema")
            local core = require("apisix.core")

            -- Valid id: lowercase alphanumeric
            local config = {
                {
                    id = "cluster1",
                    service = {
                        host = "k8s.example.com",
                        port = "6443"
                    },
                    client = {
                        token = "token123"
                    }
                }
            }
            local ok, err = core.schema.check(k8s_schema, config)
            assert(ok, err)
            ngx.say("valid id: passed")

            -- Invalid id: uppercase letters
            config[1].id = "CLUSTER1"
            ok, err = core.schema.check(k8s_schema, config)
            assert(not ok)
            ngx.say("invalid id uppercase: ", err)

            -- Invalid id: special characters
            config[1].id = "cluster-1"
            ok, err = core.schema.check(k8s_schema, config)
            assert(not ok)
            ngx.say("invalid id special char: ", err)

            -- Invalid id: too long (over 64 chars)
            config[1].id = string.rep("a", 65)
            ok, err = core.schema.check(k8s_schema, config)
            assert(not ok)
            ngx.say("invalid id too long: ", err)
        }
    }
--- response_body_like
valid id: passed
invalid id uppercase: .*
invalid id special char: .*
invalid id too long: .*



=== TEST 2: service host field validation
--- config
    location /t {
        content_by_lua_block {
            local k8s_schema = require("apisix.discovery.kubernetes.schema")
            local core = require("apisix.core")

            -- Valid host: lowercase domain
            local config = {
                {
                    id = "cluster1",
                    service = {
                        host = "k8s.example.com",
                        port = "6443"
                    },
                    client = {
                        token = "token123"
                    }
                }
            }
            local ok, err = core.schema.check(k8s_schema, config)
            assert(ok, err)
            ngx.say("valid host lowercase: passed")

            -- Valid host: uppercase domain
            config[1].service.host = "K8S.EXAMPLE.COM"
            ok, err = core.schema.check(k8s_schema, config)
            assert(not ok)
            ngx.say("invalid host uppercase: ", err)

            -- Valid host: mixed case domain
            config[1].service.host = "K8s.Example.Com"
            ok, err = core.schema.check(k8s_schema, config)
            assert(not ok)
            ngx.say("invalid host mixed case: ", err)

            -- Valid host: environment variable
            config[1].service.host = "${KUBERNETES_SERVICE_HOST}"
            ok, err = core.schema.check(k8s_schema, config)
            assert(ok, err)
            ngx.say("valid host env var: passed")

            -- Invalid host: empty string
            config[1].service.host = ""
            ok, err = core.schema.check(k8s_schema, config)
            assert(not ok)
            ngx.say("invalid host empty: ", err)
        }
    }
--- response_body_like
valid host lowercase: passed
invalid host uppercase: .*
invalid host mixed case: .*
valid host env var: passed
invalid host empty: .*
