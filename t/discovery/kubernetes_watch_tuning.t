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
no_long_string();
no_shuffle();
no_root_location();

run_tests();

__DATA__

=== TEST 1: schema accepts new watch tuning fields (single mode)
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  kubernetes:
    service:
      schema: "https"
      host: "127.0.0.1"
      port: "6443"
    client:
      token: "fake-token"
    watch_timeout_seconds: 60
    watch_jitter_seconds: 0
    watch_retry_interval_seconds: 5
    watch_retry_max_seconds: 60
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.discovery.kubernetes.schema")
            local jsonschema = require("jsonschema")
            local validator = jsonschema.generate_validator(schema)
            local ok, err = validator({
                service = { schema = "https", host = "127.0.0.1", port = "6443" },
                client  = { token = "fake-token" },
                watch_timeout_seconds        = 60,
                watch_jitter_seconds         = 0,
                watch_retry_interval_seconds = 5,
                watch_retry_max_seconds      = 60,
            })
            ngx.say(ok and "ok" or err)
        }
    }
--- request
GET /t
--- response_body
ok



=== TEST 2: schema rejects out-of-range watch_timeout_seconds
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.discovery.kubernetes.schema")
            local jsonschema = require("jsonschema")
            local validator = jsonschema.generate_validator(schema)
            local ok, err = validator({
                service = { schema = "https", host = "127.0.0.1", port = "6443" },
                client  = { token = "fake-token" },
                watch_timeout_seconds = 0,  -- minimum is 5
            })
            ngx.say(ok and "ok" or "rejected: " .. tostring(err))
        }
    }
--- request
GET /t
--- response_body_like
^rejected: .*



=== TEST 3: informer_factory.new() accepts opts and threads them through
--- config
    location /t {
        content_by_lua_block {
            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local informer = factory.new("", "v1", "Endpoints", "endpoints", "",
                { watch_timeout_seconds = 60, watch_jitter_seconds = 0 })
            ngx.say("watch_timeout_seconds=", tostring(informer.watch_timeout_seconds))
            ngx.say("watch_jitter_seconds=",  tostring(informer.watch_jitter_seconds))
        }
    }
--- request
GET /t
--- response_body
watch_timeout_seconds=60
watch_jitter_seconds=0



=== TEST 4: informer_factory.new() rejects non-table opts
--- config
    location /t {
        content_by_lua_block {
            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local _, err = factory.new("", "v1", "Endpoints", "endpoints", "", "bogus")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
opts should be a table or nil but string



=== TEST 5: informer_factory.new() with nil opts preserves backward compatibility
--- config
    location /t {
        content_by_lua_block {
            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local informer = factory.new("", "v1", "Endpoints", "endpoints", "")
            -- Defaults are applied later in watch(); the table fields are nil
            -- so the watch() function falls back to the historical 1800 / 990.
            ngx.say("default fields nil: ",
                tostring(informer.watch_timeout_seconds == nil and
                         informer.watch_jitter_seconds  == nil))
        }
    }
--- request
GET /t
--- response_body
default fields nil: true



=== TEST 6: schema accepts tuning fields in multi-mode (array form)
--- config
    location /t {
        content_by_lua_block {
            local schema = require("apisix.discovery.kubernetes.schema")
            local jsonschema = require("jsonschema")
            local validator = jsonschema.generate_validator(schema)
            local ok, err = validator({
                {
                    id      = "release",
                    service = { schema = "https", host = "127.0.0.1", port = "6443" },
                    client  = { token = "fake-token" },
                    watch_timeout_seconds        = 120,
                    watch_jitter_seconds         = 30,
                    watch_retry_interval_seconds = 10,
                    watch_retry_max_seconds      = 120,
                },
            })
            ngx.say(ok and "ok" or err)
        }
    }
--- request
GET /t
--- response_body
ok



=== TEST 7: create_handle threads watch tuning conf into informer factory and handle
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")

            local captured_opts
            local mock_factory = {
                new = function(group, version, kind, plural, namespace, opts)
                    captured_opts = opts
                    return { kind = kind }, nil
                end,
            }

            local conf = {
                service = { schema = "https", host = "127.0.0.1", port = "6443" },
                client  = { token = "fake-token" },
                watch_timeout_seconds        = 120,
                watch_jitter_seconds         = 30,
                watch_retry_interval_seconds = 10,
                watch_retry_max_seconds      = 80,
            }

            local handle, err = k8s_core.create_handle(conf, {
                endpoint_dict    = {},
                informer_factory = mock_factory,
            })
            assert(handle, err)

            ngx.say("informer watch_timeout_seconds=",
                tostring(captured_opts.watch_timeout_seconds))
            ngx.say("informer watch_jitter_seconds=",
                tostring(captured_opts.watch_jitter_seconds))
            ngx.say("handle watch_retry_interval_seconds=",
                tostring(handle.watch_retry_interval_seconds))
            ngx.say("handle watch_retry_max_seconds=",
                tostring(handle.watch_retry_max_seconds))
        }
    }
--- request
GET /t
--- response_body
informer watch_timeout_seconds=120
informer watch_jitter_seconds=30
handle watch_retry_interval_seconds=10
handle watch_retry_max_seconds=80



=== TEST 8: create_handle applies default retry intervals when omitted
--- config
    location /t {
        content_by_lua_block {
            local k8s_core = require("apisix.discovery.kubernetes.core")
            local mock_factory = {
                new = function()
                    return { kind = "Endpoints" }, nil
                end,
            }

            local handle, err = k8s_core.create_handle({
                service = { schema = "https", host = "127.0.0.1", port = "6443" },
                client  = { token = "fake-token" },
            }, {
                endpoint_dict    = {},
                informer_factory = mock_factory,
            })
            assert(handle, err)

            ngx.say("retry_interval=", tostring(handle.watch_retry_interval_seconds))
            ngx.say("retry_max=", tostring(handle.watch_retry_max_seconds))
        }
    }
--- request
GET /t
--- response_body
retry_interval=40
retry_max=40
