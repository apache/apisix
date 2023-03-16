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

log_level('warn');
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    my $extra_init_by_lua = <<_EOC_;
    local core = require("apisix.core")
    local orig_new = core.etcd.new
    core.etcd.new = function(...)
        local cli, prefix = orig_new(...)
        cli.keepalive = function(...)
            return false, "test error"
        end
        -- only simulate error once
        -- because reload would redo init()
        core.etcd.new = orig_new
        return cli, prefix
    end

    local timers = require("apisix.timers")
    local orig_unregister = timers.unregister_timer
    unregister_cnt = 0
    timers.unregister_timer = function(name, privileged)
        core.log.error("unregister timer: ", name)
        unregister_cnt = unregister_cnt + 1
        return orig_unregister(name, privileged)
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: unregister timer when etcd keepalive failed
--- yaml_config
plugins:
    - request-id
plugin_attr:
    request-id:
        snowflake:
            enable: true
            data_machine_interval: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "algorithm": "snowflake"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end

            -- wait for keepalive fails
            ngx.sleep(2)

            local code = t('/apisix/admin/plugins/reload',
                ngx.HTTP_PUT)
            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(2)
            ngx.log(ngx.ERR, unregister_cnt)
            if unregister_cnt ~= 1 then
                ngx.status = 500
            end
        }
    }
--- timeout: 5
--- error_log
lease failed
unregister timer: plugin#request-id
