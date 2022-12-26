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
    local orig_new = core.config.new
    close_cnt = 0
    core.config.new = function(key, opts)
        local obj, err = orig_new(key, opts)
        if key == "/protos" then
            local orig_close = obj.close
            obj.close = function(...)
                core.log.warn("call config close")
                close_cnt = close_cnt + 1
                return orig_close(...)
            end
        end
        return obj, err
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: close protos when grpc-transcode plugin reload
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/plugins/reload',
                ngx.HTTP_PUT)
            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(2)
            if close_cnt ~= 1 then
                ngx.status = 500
            end
        }
    }
--- error_log
call config close
