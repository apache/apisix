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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

master_on();
repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

run_tests();

__DATA__

=== TEST 1: set route(two healthy upstream nodes)
--- request
PUT /apisix/admin/routes/1
{"uri":"/server_port","upstream":{"type":"roundrobin","nodes":{"127.0.0.1:1980":1,"127.0.0.1:1981":1},"checks":{"active":{"http_path":"/status","host":"foo.com","healthy":{"interval":1,"successes":1},"unhealthy":{"interval":1,"http_failures":2}}}}}
--- error_code_like: ^20\d$
--- no_error_log
[error]



=== TEST 2: update + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, status, body = t('/apisix/admin/routes/1',
                "PUT",
                [[{"uri":"/server_port","upstream":{"type":"roundrobin","nodes":{"127.0.0.1:1980":1,"127.0.0.1:1981":1},"checks":{"active":{"http_path":"/status","healthy":{"interval":1,"successes":1},"unhealthy":{"interval":1,"http_failures":2}}}}}]]
            )

            if code < 300 then
                code = 200
            end
            ngx.say("1 code: ", code)

            ngx.sleep(0.2)
            local code, body = t('/server_port', "GET")
            ngx.say("2 code: ", code)

            ngx.sleep(0.2)
            code = t('/apisix/admin/routes/1', "DELETE")
            ngx.say("3 code: ", code)

            ngx.sleep(0.2)
            local code, body = t('/server_port', "GET")
            ngx.say("4 code: ", code)
        }
    }
--- request
GET /t
--- response_body
1 code: 200
2 code: 200
3 code: 200
4 code: 404
--- grep_error_log eval
qr/create new checker: table: 0x|try to release checker: table: 0x/
--- grep_error_log_out
create new checker: table: 0x
try to release checker: table: 0x



=== TEST 3: set route(two healthy upstream nodes)
--- request
PUT /apisix/admin/routes/1
{"uri":"/server_port","upstream":{"type":"roundrobin","nodes":{"127.0.0.1:1980":1,"127.0.0.1:1981":1},"checks":{"active":{"http_path":"/status","host":"foo.com","healthy":{"interval":1,"successes":1},"unhealthy":{"interval":1,"http_failures":2}}}}}
--- error_code: 201
--- no_error_log
[error]



=== TEST 4: update
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/server_port', "GET")
            ngx.say("1 code: ", code)

            local code, status, body = t('/apisix/admin/routes/1',
                "PUT",
                [[{"uri":"/server_port","upstream":{"type":"roundrobin","nodes":{"127.0.0.1:1980":1,"127.0.0.1:1981":1},"checks":{"active":{"http_path":"/status","healthy":{"interval":1,"successes":1},"unhealthy":{"interval":1,"http_failures":2}}}}}]]
            )

            if code < 300 then
                code = 200
            end
            ngx.say("2 code: ", code)

            ngx.sleep(0.2)
            local code, body = t('/server_port', "GET")
            ngx.say("3 code: ", code)
        }
    }
--- request
GET /t
--- response_body
1 code: 200
2 code: 200
3 code: 200
--- grep_error_log eval
qr/create new checker: table: 0x|try to release checker: table: 0x/
--- grep_error_log_out
create new checker: table: 0x
try to release checker: table: 0x
create new checker: table: 0x
