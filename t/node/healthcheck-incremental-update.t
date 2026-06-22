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

=== TEST 1: node-only change reuses the checker (no destroy-and-rebuild)
--- extra_init_worker_by_lua
    local healthcheck = require("resty.healthcheck")
    local new = healthcheck.new
    healthcheck.new = function(...)
        ngx.log(ngx.WARN, "create new checker")
        local obj = new(...)
        local clear = obj.delayed_clear
        obj.delayed_clear = function(...)
            ngx.log(ngx.WARN, "clear checker")
            return clear(...)
        end
        return obj
    end

--- config
location /t {
    content_by_lua_block {
        local checks = [[{
            "active":{
                "http_path":"/hello",
                "timeout":1,
                "type":"http",
                "healthy":{ "interval":1, "successes":1 },
                "unhealthy":{ "interval":1, "http_failures":2 }
            }
        }]]
        local function cfg(nodes)
            return [[{
                "upstream": {
                    "nodes": ]] .. nodes .. [[,
                    "type": "roundrobin",
                    "checks": ]] .. checks .. [[
                },
                "uri": "/hello"
            }]]
        end

        local t = require("lib.test_admin").test
        -- initial config: one node -> creates the checker
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1}')) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)

        -- node-only change (checks unchanged): should reconcile in place,
        -- NOT create a new checker nor delayed_clear the old one
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                 cfg('{"127.0.0.1:1980": 1, "127.0.0.1:1981": 1}')) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)
        ngx.say("done")
    }
}

--- request
GET /t
--- response_body
done
--- no_error_log
clear checker
--- error_log
create new checker
--- timeout: 8



=== TEST 2: checks-config change still rebuilds the checker
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

--- config
location /t {
    content_by_lua_block {
        local function cfg(interval)
            return [[{
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin",
                    "checks": {
                        "active":{
                            "http_path":"/hello",
                            "timeout":1,
                            "type":"http",
                            "healthy":{ "interval":]] .. interval .. [[, "successes":1 },
                            "unhealthy":{ "interval":1, "http_failures":2 }
                        }
                    }
                },
                "uri": "/hello"
            }]]
        end

        local t = require("lib.test_admin").test
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg(1)) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)
        -- change the checks config -> must rebuild (delayed_clear old checker)
        assert(t('/apisix/admin/routes/1', ngx.HTTP_PUT, cfg(2)) < 300)
        t('/hello', ngx.HTTP_GET)
        ngx.sleep(2)
        ngx.say("done")
    }
}

--- request
GET /t
--- response_body
done
--- error_log
clear checker
--- timeout: 8
