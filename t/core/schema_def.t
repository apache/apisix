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

=== TEST 1: ip_def
--- config
    location /t {
        content_by_lua_block {
            local schema_def = require("apisix.schema_def")
            local core = require("apisix.core")
            local schema = {
                type = "object",
                properties = {
                    ip = {
                        type = "string",
                        anyOf = schema_def.ip_def,
                    }
                },
            }

            local cases = {
                "127.0.0.1/1",
                "127.0.0.1/10",
                "127.0.0.1/11",
                "127.0.0.1/20",
                "127.0.0.1/21",
                "127.0.0.1/30",
                "127.0.0.1/32",
            }
            for _, c in ipairs(cases) do
                local ok, err = core.schema.check(schema, {ip = c})
                assert(ok, c)
                assert(err == nil, c)
            end

            local cases = {
                "127.0.0.1/33",
            }
            for _, c in ipairs(cases) do
                local ok, err = core.schema.check(schema, {ip = c})
                assert(not ok, c)
                assert(err ~= nil, c)
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: Missing required fields of global_rule.
--- config
    location /t {
        content_by_lua_block {
            local schema_def = require("apisix.schema_def")
            local core = require("apisix.core")

            local cases = {
                {},
                { id = "ADfwefq12D9s" },
                { id = 1 },
                {
                    plugins = {
                        foo = "bar",
                    },
                },
            }
            for _, c in ipairs(cases) do
                local ok, err = core.schema.check(schema_def.global_rule, c)
                assert(not ok)
                assert(err ~= nil)
                ngx.say("ok: ", ok, " err: ", err)
            end
        }
    }
--- request
GET /t
--- response_body eval
qr/ok: false err: property "(id|plugins)" is required/



=== TEST 3: Sanity check with minimal valid configuration.
--- config
    location /t {
        content_by_lua_block {
            local schema_def = require("apisix.schema_def")
            local core = require("apisix.core")

            local case = {
                id = 1,
                plugins = {},
            }

            local ok, err = core.schema.check(schema_def.global_rule, case)
            assert(ok)
            assert(err == nil)
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: sanity check upstream_schema
--- config
    location /t {
        content_by_lua_block {
            local schema_def = require("apisix.schema_def")
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local upstream = {
                nodes = {
                    ["127.0.0.1:8080"] = 1
                },
                type = "roundrobin",
                tls = {
                    client_cert_id = 1,
                    client_cert = ssl_cert,
                    client_key = ssl_key
                }
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(not ok)
            assert(err ~= nil)

            upstream = {
                nodes = {
                    ["127.0.0.1:8080"] = 1
                },
                type = "roundrobin",
                tls = {
                    client_cert_id = 1
                }
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(ok)
            assert(err == nil, err)

            upstream = {
                nodes = {
                    ["127.0.0.1:8080"] = 1
                },
                type = "roundrobin",
                tls = {
                    client_cert = ssl_cert,
                    client_key = ssl_key
                }
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(ok)
            assert(err == nil, err)

            upstream = {
                nodes = {
                    ["127.0.0.1:8080"] = 1
                },
                type = "roundrobin",
                tls = {
                }
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(ok)
            assert(err == nil, err)

            upstream = {
                nodes = {
                    ["127.0.0.1:8080"] = 1
                },
                type = "roundrobin",
                tls = {
                    client_cert = ssl_cert
                }
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(not ok)
            assert(err ~= nil)

            upstream = {
                nodes = {
                    ["127.0.0.1:8080"] = 1
                },
                type = "roundrobin",
                tls = {
                    client_cert_id = 1,
                    client_key = ssl_key
                }
            }
            local ok, err = core.schema.check(schema_def.upstream, upstream)
            assert(not ok)
            assert(err ~= nil)

            ngx.say("passed")
        }
    }
--- response_body
passed
