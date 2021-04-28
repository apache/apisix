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
    $ENV{"ETCD_ENABLE_AUTH"} = "false";
    delete $ENV{"FLUSH_ETCD"};
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

# Authentication is enabled at etcd and credentials are set
system('etcdctl --endpoints="http://127.0.0.1:2379" user add root:5tHkHhYkjr6cQY');
system('etcdctl --endpoints="http://127.0.0.1:2379" role add root');
system('etcdctl --endpoints="http://127.0.0.1:2379" user grant-role root root');
system('etcdctl --endpoints="http://127.0.0.1:2379" role list');
system('etcdctl --endpoints="http://127.0.0.1:2379" user user list');
# Grant the user access to the specified directory
system('etcdctl --endpoints="http://127.0.0.1:2379" user add apisix:abc123');
system('etcdctl --endpoints="http://127.0.0.1:2379" role add apisix');
system('etcdctl --endpoints="http://127.0.0.1:2379" user grant-role apisix apisix');
system('etcdctl --endpoints=http://127.0.0.1:2379 role grant-permission apisix --prefix=true readwrite /apisix/');
system('etcdctl --endpoints="http://127.0.0.1:2379" auth enable');

run_tests;

# Authentication is disabled at etcd
system('etcdctl --endpoints="http://127.0.0.1:2379" --user root:5tHkHhYkjr6cQY auth disable');
system('etcdctl --endpoints="http://127.0.0.1:2379" user delete root');
system('etcdctl --endpoints="http://127.0.0.1:2379" role delete root');
system('etcdctl --endpoints="http://127.0.0.1:2379" user delete apisix');
system('etcdctl --endpoints="http://127.0.0.1:2379" role delete apisix');
__DATA__

=== TEST 1: Set and Get a value pass
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local key = "/test_key"
            local val = "test_value"
            local res, err = core.etcd.set(key, val)
            ngx.say(err)
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log eval
qr /insufficient credentials code: 401/



=== TEST 2: etcd grants permissions with a different prefix than the one used by apisix, etcd will forbidden
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local key = "/test_key"
            local val = "test_value"
            local res, err = core.etcd.set(key, val)
            ngx.say(err)
        }
    }
--- yaml_config
etcd:
  host:
    - "http://127.0.0.1:2379"
  prefix: "/apisix"
  user: apisix
  password: abc123
--- request
GET /t
--- error_log eval
qr /etcd forbidden code: 403/
