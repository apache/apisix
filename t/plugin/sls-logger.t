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

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your-project", logstore = "your-logstore"
            , access_key_id = "your_access_key", access_key_secret = "your_access_secret"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: missing access_key_secret
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your-project", logstore = "your-logstore"
            , access_key_id = "your_access_key"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "access_key_secret" is required
done



=== TEST 3: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local ok, err = plugin.check_schema({host = "cn-zhangjiakou-intranet.log.aliyuncs.com", port = 10009, project = "your_project", logstore = "your_logstore"
            , access_key_id = "your_access_key", access_key_secret = "your_access_secret", timeout = "10"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "timeout" validation failed: wrong type: expected integer, got string
done



=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "sls-logger": {
                                "host": "100.100.99.135",
                                "port": 10009,
                                "project": "your_project",
                                "logstore": "your_logstore",
                                "access_key_id": "your_access_key_id",
                                "access_key_secret": "your_access_key_secret",
                                "timeout": 30000
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "sls-logger": {
                                    "host": "100.100.99.135",
                                    "port": 10009,
                                    "project": "your_project",
                                    "logstore": "your_logstore",
                                    "access_key_id": "your_access_key_id",
                                    "access_key_secret": "your_access_key_secret",
                                    "timeout": 30000
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: access
--- request
GET /hello
--- response_body
hello world
--- wait: 1



=== TEST 6: test combine log
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sls-logger")
            local entities = {}
            table.insert(entities, {data = "1"})
            table.insert(entities, {data = "2"})
            table.insert(entities, {data = "3"})
            local data =  plugin.combine_syslog(entities)
            ngx.say(data)
        }
    }
--- response_body
123



=== TEST 7: sls log get milliseconds
--- config
    location /t {
        content_by_lua_block {
            local function get_syslog_timestamp_millisecond(log_entry)
                local first_idx = string.find(log_entry, " ") + 1
                local last_idx2 = string.find(log_entry, " ", first_idx)
                local rfc3339_date = string.sub(log_entry, first_idx, last_idx2)
                local rfc3339_len = string.len(rfc3339_date)
                local rfc3339_millisecond = string.sub(rfc3339_date, rfc3339_len - 4, rfc3339_len - 2)
                return tonumber(rfc3339_millisecond)
            end

            math.randomseed(os.time())
            local rfc5424 = require("apisix.plugins.slslog.rfc5424")
            local m = 0
            -- because the millisecond value obtained by `ngx.now` may be `0`
            -- it is executed multiple times to ensure the accuracy of the test
            for i = 1, 5 do
                ngx.sleep(string.format("%0.3f", math.random()))
                local log_entry = rfc5424.encode("SYSLOG", "INFO", "localhost", "apisix",
                                                 123456, "apisix.apache.org", "apisix.apache.log",
                                                 "apisix.sls.logger", "BD274822-96AA-4DA6-90EC-15940FB24444",
                                                 "hello world")
                m = get_syslog_timestamp_millisecond(log_entry) + m
            end

            if m > 0 then
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
--- timeout: 5
