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
log_level('warn');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: ensure the old check is cleared after configuration updated
--- extra_init_worker_by_lua
    local healthcheck = require("resty.healthcheck")
    local new = healthcheck.new
    healthcheck.new = function(...)
        local obj = new(...)
        local clear = obj.delayed_clear
        obj.delayed_clear = function(...)
            ngx.log(ngx.WARN, "clear checker")
            return clear(...)
        end
        return obj
    end

--- extra_init_by_lua
    local utils = require("apisix.core.utils")
    local count = 0
    utils.dns_parse = function (domain)  -- mock: DNS parser
        count = count + 1
        if domain == "test1.com" then
            return {address = "127.0.0." .. count}
        end
        if domain == "test2.com" then
            return {address = "127.0.0." .. count+100}
        end

        error("unknown domain: " .. domain)
    end

--- config
location /t {
    content_by_lua_block {
        local cfg = [[{
            "upstream": {
                "nodes": {
                    "test1.com:1980": 1,
                    "test2.com:1980": 1
                },
                "type": "roundrobin",
                "checks":{
                    "active":{
                        "healthy":{
                            "http_statuses":[
                                200,
                                302
                            ],
                            "interval":1,
                            "successes":2
                        },
                        "http_path":"/hello",
                        "timeout":1,
                        "type":"http",
                        "unhealthy":{
                            "http_failures":5,
                            "http_statuses":[
                                429,
                                404,
                                500,
                                501,
                                502,
                                503,
                                504,
                                505
                            ],
                            "interval":1,
                            "tcp_failures":2,
                            "timeouts":3
                        }
                    }
                }
            },
            "uri": "/hello"
        }]]
        local t = require("lib.test_admin").test
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg) < 300)
        t('/hello', ngx.HTTP_GET)
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg) < 300)
        ngx.sleep(1)
    }
}

--- request
GET /t
--- error_log
clear checker
