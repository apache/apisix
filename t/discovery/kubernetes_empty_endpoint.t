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
log_level("warn");

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

=== TEST 1: on_endpoint_modified preserves previous endpoints when payload is empty
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")
            local cbs = k8s_core.create_endpoint_callbacks({})

            local handle = {
                endpoint_dict = ngx.shared["kubernetes"],
                default_weight = 50,
                namespace_selector = nil,
                endpoint_slices_cache = {},
                current_keys_hash = {},
            }

            -- 1) seed with a normal endpoint
            local normal = {
                metadata = { namespace = "default", name = "svc1" },
                subsets = {
                    {
                        addresses = { { ip = "10.0.0.1" } },
                        ports = { { name = "http", port = 80 } },
                    },
                },
            }
            cbs.on_endpoint_modified(handle, normal)
            local v1 = handle.endpoint_dict:get("default/svc1#version")
            local c1 = handle.endpoint_dict:get("default/svc1")
            assert(v1 ~= nil, "version should be set after first update")
            assert(c1 and c1:find("10.0.0.1"), "content should contain 10.0.0.1")
            ngx.say("seeded version=", tostring(v1 ~= nil), " content_has_ip=", tostring(c1:find("10.0.0.1") ~= nil))

            -- 2) deliver a "transient empty" event: subsets exist but addresses is nil
            local transient_empty = {
                metadata = { namespace = "default", name = "svc1" },
                subsets = {
                    {
                        notReadyAddresses = { { ip = "10.0.0.1" } },
                        ports = { { name = "http", port = 80 } },
                    },
                },
            }
            cbs.on_endpoint_modified(handle, transient_empty)

            -- 3) the previous endpoint must still be present (this is the bug fix)
            local v2 = handle.endpoint_dict:get("default/svc1#version")
            local c2 = handle.endpoint_dict:get("default/svc1")
            assert(v2 == v1, "version must be unchanged after empty update; got " .. tostring(v2))
            assert(c2 == c1, "content must be unchanged after empty update")
            ngx.say("after empty: version_unchanged=", tostring(v2 == v1),
                    " content_unchanged=", tostring(c2 == c1))

            -- 4) deliver an entirely empty subsets payload too
            local subsets_empty = {
                metadata = { namespace = "default", name = "svc1" },
                subsets = {},
            }
            cbs.on_endpoint_modified(handle, subsets_empty)
            local v3 = handle.endpoint_dict:get("default/svc1#version")
            assert(v3 == v1, "version must be unchanged after subsets=[] update")
            ngx.say("after subsets=[]: version_unchanged=", tostring(v3 == v1))

            -- 5) a real new endpoint event still updates as expected
            local new = {
                metadata = { namespace = "default", name = "svc1" },
                subsets = {
                    {
                        addresses = { { ip = "10.0.0.2" } },
                        ports = { { name = "http", port = 80 } },
                    },
                },
            }
            cbs.on_endpoint_modified(handle, new)
            local c4 = handle.endpoint_dict:get("default/svc1")
            assert(c4 and c4:find("10.0.0.2"), "content should be updated to 10.0.0.2")
            ngx.say("after recover: content_has_new_ip=", tostring(c4:find("10.0.0.2") ~= nil))
        }
    }
--- response_body
seeded version=true content_has_ip=true
after empty: version_unchanged=true content_unchanged=true
after subsets=[]: version_unchanged=true
after recover: content_has_new_ip=true
--- error_log
kubernetes discovery: endpoint has no ready addresses
kubernetes discovery: skip empty endpoint update for default/svc1



=== TEST 2: on_endpoint_slices_modified preserves previous endpoints when no slice has ready endpoints
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")
            local cbs = k8s_core.create_endpoint_callbacks({})

            local handle = {
                endpoint_dict = ngx.shared["kubernetes"],
                default_weight = 50,
                namespace_selector = nil,
                endpoint_slices_cache = {},
                current_keys_hash = {},
            }

            -- 1) seed with a normal slice
            local seed_slice = {
                metadata = {
                    namespace = "default",
                    name = "svc1-slice-aaa",
                    labels = { ["kubernetes.io/service-name"] = "svc1" },
                },
                endpoints = {
                    {
                        addresses = { "10.0.0.1" },
                        conditions = { ready = true },
                    },
                },
                ports = { { name = "http", port = 80 } },
            }
            cbs.on_endpoint_slices_modified(handle, seed_slice)
            local v1 = handle.endpoint_dict:get("default/svc1#version")
            local c1 = handle.endpoint_dict:get("default/svc1")
            assert(v1, "version should be set")
            assert(c1 and c1:find("10.0.0.1"), "content should contain 10.0.0.1")

            -- 2) deliver an update where the same slice now has an unready endpoint
            local empty_slice = {
                metadata = {
                    namespace = "default",
                    name = "svc1-slice-aaa",
                    labels = { ["kubernetes.io/service-name"] = "svc1" },
                },
                endpoints = {
                    {
                        addresses = { "10.0.0.1" },
                        conditions = { ready = false },
                    },
                },
                ports = { { name = "http", port = 80 } },
            }
            cbs.on_endpoint_slices_modified(handle, empty_slice)
            local v2 = handle.endpoint_dict:get("default/svc1#version")
            local c2 = handle.endpoint_dict:get("default/svc1")
            assert(v2 == v1, "version must be unchanged after all-not-ready slice update")
            assert(c2 == c1, "content must be unchanged after all-not-ready slice update")
            ngx.say("ok preserved=", tostring(v2 == v1 and c2 == c1))
        }
    }
--- response_body
ok preserved=true
--- error_log
kubernetes discovery: skip empty endpoint update for default/svc1
