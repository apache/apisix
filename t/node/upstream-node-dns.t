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
log_level('info');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: route with one upstream node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "test.com:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: hit route, resolve upstream node to "127.0.0.2" always
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    utils.dns_parse = function (domain)  -- mock: DNS parser
        if domain == "test.com" then
            return {address = "127.0.0.2"}
        end

        error("unknown domain: " .. domain)
    end
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 3: hit route, resolve upstream node to different values
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    local count = 0
    utils.dns_parse = function (domain)  -- mock: DNS parser
        count = count + 1

        if domain == "test.com" then
            return {address = "127.0.0." .. count}
        end

        error("unknown domain: " .. domain)
    end

--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)
    }
}

--- request
GET /t
--- grep_error_log eval
qr/dns resolver domain: test.com to 127.0.0.\d|call \/hello|proxy request to 127.0.0.\d:1980/
--- grep_error_log_out
call /hello
dns resolver domain: test.com to 127.0.0.1
proxy request to 127.0.0.1:1980



=== TEST 4: set route with two upstream nodes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "test.com:1980": 1,
                            "test2.com:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: hit route, resolve the upstream node to "127.0.0.2"
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    utils.dns_parse = function (domain)  -- mock: DNS parser
        if domain == "test.com" or domain == "test2.com" then
            return {address = "127.0.0.2"}
        end

        error("unknown domain: " .. domain)
    end
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 6: hit route, resolve upstream node to different values
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    local count = 0
    utils.dns_parse = function (domain)  -- mock: DNS parser
        count = count + 1

        if domain == "test.com" or domain == "test2.com" then
            return {address = "127.0.0." .. count}
        end

        error("unknown domain: " .. domain)
    end

--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)
        core.log.warn("code: ", code)
    }
}

--- request
GET /t
--- grep_error_log eval
qr/dns resolver domain: \w+.com to 127.0.0.\d|call \/hello|proxy request to 127.0.0.\d:1980/
--- grep_error_log_out eval
qr/call \/hello(
dns resolver domain: test.com to 127.0.0.1
dns resolver domain: test2.com to 127.0.0.2|
dns resolver domain: test2.com to 127.0.0.1
dns resolver domain: test.com to 127.0.0.2)
proxy request to 127.0.0.[12]:1980
/



=== TEST 7: upstream with one upstream node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "test.com:1980": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: set route with upstream_id 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream_id": "1"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: hit route, resolve upstream node to different values
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    local count = 0
    utils.dns_parse = function (domain)  -- mock: DNS parser
        count = count + 1

        if domain == "test.com" then
            return {address = "127.0.0." .. count}
        end

        error("unknown domain: " .. domain)
    end

--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)
    }
}

--- request
GET /t
--- grep_error_log eval
qr/dns resolver domain: test.com to 127.0.0.\d|call \/hello|proxy request to 127.0.0.\d:1980/
--- grep_error_log_out
call /hello
dns resolver domain: test.com to 127.0.0.1
proxy request to 127.0.0.1:1980



=== TEST 10: two upstream nodes in upstream object
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "test.com:1980": 1,
                        "test2.com:1980": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: hit route, resolve upstream node to different values
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    local count = 0
    utils.dns_parse = function (domain)  -- mock: DNS parser
        count = count + 1

        if domain == "test.com" or domain == "test2.com" then
            return {address = "127.0.0." .. count}
        end

        error("unknown domain: " .. domain)
    end

--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)
    }
}

--- request
GET /t
--- grep_error_log eval
qr/dns resolver domain: \w+.com to 127.0.0.\d|call \/hello|proxy request to 127.0.0.\d:1980/
--- grep_error_log_out eval
qr/call \/hello(
dns resolver domain: test.com to 127.0.0.1
dns resolver domain: test2.com to 127.0.0.2|
dns resolver domain: test2.com to 127.0.0.1
dns resolver domain: test.com to 127.0.0.2)
proxy request to 127.0.0.[12]:1980
/



=== TEST 12: dns cached expired, resolve the domain always with same value
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    local count = 1
    utils.dns_parse = function (domain)  -- mock: DNS parser
        if domain == "test.com" or domain == "test2.com" then
            return {address = "127.0.0.1"}
        end

        error("unknown domain: " .. domain)
    end

--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)
    }
}

--- request
GET /t
--- grep_error_log eval
qr/dns resolver domain: \w+.com to 127.0.0.\d|call \/hello|proxy request to 127.0.0.\d:1980/
--- grep_error_log_out eval
qr/call \/hello(
dns resolver domain: test.com to 127.0.0.1
dns resolver domain: test2.com to 127.0.0.1|
dns resolver domain: test2.com to 127.0.0.1
dns resolver domain: test.com to 127.0.0.1)
proxy request to 127.0.0.1:1980
/



=== TEST 13: two upstream nodes in upstream object (one host + one IP)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": {
                        "test.com:1980": 1,
                        "127.0.0.5:1981": 1
                    },
                    "type": "roundrobin",
                    "desc": "new upstream"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 14: dns cached expired, resolve the domain with different values
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    local count = 0
    utils.dns_parse = function (domain)  -- mock: DNS parser
        count = count + 1
        if domain == "test.com" or domain == "test2.com" then
            return {address = "127.0.0." .. count}
        end

        error("unknown domain: " .. domain)
    end

--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)
    }
}

--- request
GET /t
--- grep_error_log eval
qr/dns resolver domain: \w+.com to 127.0.0.\d|call \/hello|proxy request to 127.0.0.\d:198\d/
--- grep_error_log_out eval
qr/call \/hello
dns resolver domain: test.com to 127.0.0.1
proxy request to 127.0.0.(1:1980|5:1981)
/
