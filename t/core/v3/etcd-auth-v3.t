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
BEGIN {
    $ENV{"ETCD_ENABLE_AUTH"} = "true";
    $ENV{"ETCDCTL_API"} = "3"
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    my $init_by_lua_block = <<_EOC_;
    fetch_local_conf = require("apisix.core.config_local").local_conf

    function check_val(res)
        local local_conf, err = fetch_local_conf()
            if not local_conf then
            return nil, nil, err
        end
        ver = local_conf.etcd.version

        if ver == "v3" then
            ngx.say(res.body.kvs[1].value)
        else
            ngx.say(res.body.node.value)
        end
    end
_EOC_
    $block->set_value("init_by_lua_block", $init_by_lua_block);
});

# Authentication is enabled at etcd and credentials are set
system('etcdctl --endpoints="http://127.0.0.1:2379" --user root:5tHkHhYkjr6cQY user add root:5tHkHhYkjr6cQY');
system('etcdctl --endpoints="http://127.0.0.1:2379" --user root:5tHkHhYkjr6cQY auth enable');

run_tests;

# Authentication is disabled at etcd & guest access is granted
system('etcdctl --endpoints="http://127.0.0.1:2379" --user root:5tHkHhYkjr6cQY auth disable');


__DATA__

=== TEST 1: Set and Get a value pass with authentication
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local key = "/test_key"
            local val = "test_value"
            core.etcd.set(key, val)
            local res, err = core.etcd.get(key)
            check_val(res)
            core.etcd.delete(key)
        }
    }
--- request
GET /t
--- response_body
test_value
--- no_error_log
[error]
