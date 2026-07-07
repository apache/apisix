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
log_level("info");

run_tests;

__DATA__

=== TEST 1: create first global rule with limit-count plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- error_code: 201



=== TEST 2: try to create second global rule with same plugin (should fail)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 5,
                            "time_window": 120,
                            "rejected_code": 429,
                            "key": "remote_addr"
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/plugin 'limit-count' already exists in global rule with id '1'/
--- error_code: 400



=== TEST 3: create second global rule with different plugin (should succeed)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ip-restriction": {
                            "whitelist": ["127.0.0.0/24"]
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- error_code: 201



=== TEST 4: try to create third global rule with plugin from first rule (should fail)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/3',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 10,
                            "time_window": 30,
                            "rejected_code": 429,
                            "key": "remote_addr"
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/plugin 'limit-count' already exists in global rule with id '1'/
--- error_code: 400



=== TEST 5: try to create global rule with multiple plugins where one conflicts (should fail)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/3',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 1,
                            "burst": 0,
                            "key": "remote_addr"
                        },
                        "ip-restriction": {
                            "whitelist": ["192.168.0.0/16"]
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- response_body_like eval
qr/plugin 'ip-restriction' already exists in global rule with id '2'/
--- error_code: 400



=== TEST 6: update existing global rule with its current plugin (should succeed)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-count": {
                            "count": 3,
                            "time_window": 90,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    }
                }]]
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- error_code: 200



=== TEST 7: prepare data to test removal (during global rule execution) of global rules with re-occurring plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local http = require("resty.http")

            local plugin_conf = function(id_val, count_val, t_val)
                return {
                    id = id_val,
                    create_time = 1764938795,
                    update_time = 1764938811,
                    plugins = {
                        ["limit-count"] = {
                            key_type = "var",
                            show_limit_quota_header = true,
                            rejected_code = 503,
                            policy = "local",
                            key = "remote_addr",
                            allow_degradation = false,
                            count = count_val,
                            time_window = t_val
                        }
                    }
                }
            end

            etcd.set("/global_rules/1", plugin_conf(1, 2, 10))
            etcd.set("/global_rules/2", plugin_conf(2, 3, 60))
            etcd.set("/global_rules/3", plugin_conf(3, 5, 20))

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_code: 200



=== TEST 8: re-occuring plugins in global rules should be removed and not executed
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")


            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/hello")

            if not res then
                ngx.say(err)
                return
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_code: 200
--- no_error_log
limit key: global_rule
--- error_log
Found limit-count configured across different global rules. Removing it from execution list
