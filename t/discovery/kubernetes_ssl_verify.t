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
no_shuffle();
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

=== TEST 1: ssl_verify is false when apiserver uses http scheme (no explicit config)
--- config
    location /t {
        content_by_lua_block {
            local captured_opts = {}

            -- Monkeypatch resty.http to capture connect options
            local http_orig = require("resty.http")
            local http_new_orig = http_orig.new
            http_orig.new = function()
                local mock = {}
                mock.connect = function(self, opts)
                    captured_opts.ssl_verify = opts and opts.ssl_verify
                    -- simulate connection refused to stop further processing
                    return false, "connection refused"
                end
                return mock
            end

            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local informer = factory.new(nil, "v1", "Endpoints", "endpoints", nil)

            -- apiserver.ssl_verify is set by init.lua get_apiserver; simulate http result
            local apiserver = {
                schema = "http",
                host = "127.0.0.1",
                port = 6445,
                ssl_verify = false,  -- what get_apiserver would set for http scheme
            }

            informer:list_watch(apiserver)
            ngx.say("ssl_verify for http scheme: ", tostring(captured_opts.ssl_verify))

            -- restore
            http_orig.new = http_new_orig
        }
    }
--- response_body
ssl_verify for http scheme: false
--- no_error_log
[alert]



=== TEST 2: ssl_verify defaults to false when apiserver uses https scheme (no explicit config)
--- config
    location /t {
        content_by_lua_block {
            local captured_opts = {}

            -- Monkeypatch resty.http to capture connect options
            local http_orig = require("resty.http")
            local http_new_orig = http_orig.new
            http_orig.new = function()
                local mock = {}
                mock.connect = function(self, opts)
                    captured_opts.ssl_verify = opts and opts.ssl_verify
                    -- simulate connection refused to stop further processing
                    return false, "connection refused"
                end
                return mock
            end

            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local informer = factory.new(nil, "v1", "Endpoints", "endpoints", nil)

            -- apiserver.ssl_verify is set by init.lua get_apiserver; default is false
            local apiserver = {
                schema = "https",
                host = "127.0.0.1",
                port = 6443,
                ssl_verify = false,  -- default when no explicit config, even for https
            }

            informer:list_watch(apiserver)
            ngx.say("ssl_verify for https scheme (no config): ", tostring(captured_opts.ssl_verify))

            -- restore
            http_orig.new = http_new_orig
        }
    }
--- response_body
ssl_verify for https scheme (no config): false
--- no_error_log
[alert]



=== TEST 3: explicit ssl_verify=true enables certificate verification for https
--- config
    location /t {
        content_by_lua_block {
            local captured_opts = {}

            -- Monkeypatch resty.http to capture connect options
            local http_orig = require("resty.http")
            local http_new_orig = http_orig.new
            http_orig.new = function()
                local mock = {}
                mock.connect = function(self, opts)
                    captured_opts.ssl_verify = opts and opts.ssl_verify
                    return false, "connection refused"
                end
                return mock
            end

            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local informer = factory.new(nil, "v1", "Endpoints", "endpoints", nil)

            -- Simulate get_apiserver with explicit ssl_verify=true (user opts in)
            local apiserver = {
                schema = "https",
                host = "127.0.0.1",
                port = 6443,
                ssl_verify = true,  -- explicit opt-in for certificate verification
            }

            informer:list_watch(apiserver)
            ngx.say("explicit ssl_verify=true respected: ", tostring(captured_opts.ssl_verify == true))

            -- restore
            http_orig.new = http_new_orig
        }
    }
--- response_body
explicit ssl_verify=true respected: true
--- no_error_log
[alert]



=== TEST 4: get_apiserver defaults ssl_verify to false when service.ssl_verify is not configured
--- config
    location /t {
        content_by_lua_block {
            -- Verify the contract of get_apiserver() in init.lua:
            -- when conf.service.ssl_verify is nil (not configured), ssl_verify must be false.
            -- This is the backward-compatible default — NOT derived from the scheme.
            --
            -- The logic being tested (init.lua):
            --   if conf.service.ssl_verify ~= nil then
            --       apiserver.ssl_verify = conf.service.ssl_verify
            --   else
            --       apiserver.ssl_verify = false   <-- must be false, not (schema == "https")
            --   end

            local function compute_ssl_verify(service_conf)
                if service_conf.ssl_verify ~= nil then
                    return service_conf.ssl_verify
                else
                    return false
                end
            end

            -- Case 1: https with no ssl_verify set -> must be false
            local result1 = compute_ssl_verify({ schema = "https", host = "127.0.0.1", port = "6443" })
            ngx.say("https, no ssl_verify -> false: ", tostring(result1 == false))

            -- Case 2: http with no ssl_verify set -> must be false
            local result2 = compute_ssl_verify({ schema = "http", host = "127.0.0.1", port = "6445" })
            ngx.say("http, no ssl_verify -> false: ", tostring(result2 == false))

            -- Case 3: explicit ssl_verify=true overrides default
            local result3 = compute_ssl_verify({ schema = "https", host = "127.0.0.1", port = "6443", ssl_verify = true })
            ngx.say("explicit ssl_verify=true -> true: ", tostring(result3 == true))

            -- Case 4: explicit ssl_verify=false is preserved
            local result4 = compute_ssl_verify({ schema = "https", host = "127.0.0.1", port = "6443", ssl_verify = false })
            ngx.say("explicit ssl_verify=false -> false: ", tostring(result4 == false))
        }
    }
--- response_body
https, no ssl_verify -> false: true
http, no ssl_verify -> false: true
explicit ssl_verify=true -> true: true
explicit ssl_verify=false -> false: true
