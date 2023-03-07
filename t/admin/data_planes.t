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
no_shuffle();
log_level("warn");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: test /apisix/admin/data_planes
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)
            local t = require("lib.test_admin").test
            local json = require('cjson')
            local code, _, body = t("/apisix/admin/data_planes", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local tab = json.decode(body)
            assert(#tab >= 1, "GET /apisix/admin/data_planes does not return JSON array")

            local code, _, body = t("/apisix/admin/data_planes/" .. tab[1].value.id, "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local tab2 = json.decode(body)
            assert(#tab2 == 0, "GET /apisix/admin/data_planes/<id> does not return JSON object")
            assert(tab2.value.id == tab[1].value.id, "id mismatch")
            table.insert(tab, tab2)

            for _, info in ipairs(tab) do
                assert(ngx.re.match(info.value.hostname, [[[a-zA-Z\-0-9\.]+]]), "invalid hostname")
                assert(ngx.re.match(info.value.boot_time, [[\d+]]), "invalid boot_time")
                assert(ngx.re.match(info.value.etcd_version, [[[\d\.]+]]), "invalid etcd_version")
                assert(ngx.re.match(info.value.id, [[[a-zA-Z\-0-9]+]]), "invalid id")
                assert(ngx.re.match(info.value.version, [[[\d\.]+]]), "invalid version")
            end
        }
    }
