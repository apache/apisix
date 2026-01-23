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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_yaml_config = <<_EOC_;
plugins:
    - skywalking
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    my $extra_init_by_lua = <<_EOC_;
    -- reduce default report interval
    local client = require("skywalking.client")
    client.backendTimerDelay = 0.5
    local initialized = false
    client.startBackendTimer = function(self, backend_http_uri)
        initialized = true
        self.stopped = false
        local metadata_buffer = ngx.shared.tracing_buffer

        -- The codes of timer setup is following the OpenResty timer doc
        local new_timer = ngx.timer.at
        local check

        local log = ngx.log
        local ERR = ngx.ERR

        check = function(premature)
            if not premature and not self.stopped then
                log(ngx.INFO, "running timer")
                local instancePropertiesSubmitted = metadata_buffer:get('instancePropertiesSubmitted')
                if (instancePropertiesSubmitted == nil or instancePropertiesSubmitted == false) then
                    self:reportServiceInstance(metadata_buffer, backend_http_uri)
                else
                    self:ping(metadata_buffer, backend_http_uri)
                end

                self:reportTraces(metadata_buffer, backend_http_uri)

                -- do the health check
                local ok, err = new_timer(self.backendTimerDelay, check)
                if not ok then
                    log(ERR, "failed to create timer: ", err)
                    return
                end
            end
        end

        if 0 == ngx.worker.id() then
            -- patch: skywalking2
            -- Ensure that it is executed only once
            ngx.log(ngx.INFO, "start skywalking backend timer")
            local ok, err = new_timer(self.backendTimerDelay, check)
            if not ok then
                log(ERR, "failed to create timer: ", err)
                return
            end
        end
    end


    local sw_tracer = require("skywalking.tracer")
    local inject = function(mod, name)
        local old_f = mod[name]
        mod[name] = function (...)
            ngx.log(ngx.WARN, "skywalking run ", name)
            return old_f(...)
        end
    end

    inject(sw_tracer, "start")
    inject(sw_tracer, "finish")
    inject(sw_tracer, "prepareForReport")
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);

    $block;
});

workers(4);
repeat_each(1);
no_long_string();
no_root_location();
log_level("debug");

run_tests;

__DATA__

=== TEST 1: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "skywalking": {
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: trigger skywalking
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/opentracing"
            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say("failed to request: ", err)
                    ngx.exit(500)
                end
                if res.status ~= 200 then
                    ngx.say("failed to request: ", res.status)
                    ngx.exit(500)
                end
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/start skywalking backend timer/
--- grep_error_log_out
start skywalking backend timer
--- wait: 1
