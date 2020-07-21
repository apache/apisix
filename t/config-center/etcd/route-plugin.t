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
    $ENV{"ETCD_ENABLE_AUTH"} = "true"
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

# Authentication is enabled at etcd and credentials are set
system('etcdctl --endpoints="http://127.0.0.1:2379" -u root:5tHkHhYkjr6cQY user add root:5tHkHhYkjr6cQY');
system('etcdctl --endpoints="http://127.0.0.1:2379" -u root:5tHkHhYkjr6cQY auth enable');
system('etcdctl --endpoints="http://127.0.0.1:2379" -u root:5tHkHhYkjr6cQY role revoke --path "/*" -rw guest');

run_tests;

# Authentication is disabled at etcd & guest access is granted
system('etcdctl --endpoints="http://127.0.0.1:2379" -u root:5tHkHhYkjr6cQY auth disable');
system('etcdctl --endpoints="http://127.0.0.1:2379" -u root:5tHkHhYkjr6cQY role grant --path "/*" -rw guest');

__DATA__

=== TEST 1: set route with plugin
--- config
    location /t {
        content_by_lua_block {
            local conf = {
                ["uri"] = "/hello",
                ["plugins"] = {
                    ["proxy-rewrite"] = {
                        ["uri"] = "/uri/plugin_proxy_rewrite",
                        ["headers"] = {
                            "X-Api-Version": "v2"
                        }
                    }
                },
                ["upstream"] = {
                    ["nodes"] = {
                        ["127.0.0.1:1980"]: 1
                    },
                    ["type"]: "roundrobin"
                }
            }
            local res, err = core.etcd.push("/routes", conf)
            if not res then
                core.log.error("failed to post route[/routes] to etcd")
                ngx.exit(code)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: route with plugin
--- request
GET /hello
--- more_headers
X-Api-Version:v1
--- response_body
uri: /uri/plugin_proxy_rewrite
host: localhost
x-api-version: v2
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 3: set route with invalid plugin
--- config
    location /t {
        content_by_lua_block {
            local sub_str  = string.sub
            local res, err = core.etcd.get("/routes")
            if not res then
                core.log.error("failed to get route[/routes] from etcd: ", err)
            local key = sub_str(res.body.node.nodes[1].key, 8)
            local conf = {
                ["uri"] = "/hello",
                ["plugins"] = {
                    ["proxy-rewrite"] = {
                        ["uri"] = "/uri/plugin_proxy_rewrite",
                        ["headers"] = {
                            "": ""
                        }
                    }
                },
                ["upstream"] = {
                    ["nodes"] = {
                        ["127.0.0.1:1980"]: 1
                    },
                    ["type"]: "roundrobin"
                }
            }
            local res, err = core.etcd.set(key, conf)
            if not res then
                core.log.error("failed to put route[/routes] to etcd")
                ngx.exit(code)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 4: route with invalid plugin
--- request
GET /hello
--- error_code: 404
--- error_log
failed to check the configuration of plugin proxy-rewrite err: invalid type as header value, context: ngx.timer
