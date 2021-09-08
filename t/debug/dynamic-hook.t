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
workers(4);

sub read_file($) {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $debug_config = read_file("conf/debug.yaml");

run_tests();

__DATA__

=== TEST 1: dynamic enable
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/v1/advance_debug',
                ngx.HTTP_POST,
                [[{
                    "enable": true,
                    "is_print_input_args": true,
                    "is_print_return_value": true,
                    "log_level":"warn",
                    "name":"hook_phase",
                    "hook_phase": {
                        "apisix": [
                            "http_access_phase",
                            "http_header_filter_phase"
                        ]
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(1.1) -- wait for debug timer start

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(0.6) -- wait for sync

            local code, err, org_body = t('/hello')
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(1.1) -- wait for debug timer exec

            ngx.print(org_body)
        }
    }
--- request
GET /t
--- wait: 3
--- timeout: 5
--- response_body
hello world
--- error_log
call require("apisix").http_access_phase() args:{}
call require("apisix").http_access_phase() return:{}
call require("apisix").http_header_filter_phase() args:{}
call require("apisix").http_header_filter_phase() return:{}
--- no_error_log
call require("apisix").http_body_filter_phase() args:{}
call require("apisix").http_body_filter_phase() return:{}
call require("apisix").http_log_phase() args:{}
call require("apisix").http_log_phase() return:{}



=== TEST 2: no module and function list to hook
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/v1/advance_debug',
                ngx.HTTP_POST,
                [[{
                    "dynamic_enable":true,
                    "is_print_input_args":true,
                    "is_print_return_value":true,
                    "log_level":"warn",
                    "name":"hook_phase",
                    "hook_phase": {
                    }
                }]]
            )
            ngx.status = code
        }
    }
--- request
GET /t
--- error_code: 400
--- ignore_response_body
--- error_log
no module and function list to hook
--- no_error_log
[error]



=== TEST 3: dynamic disable
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/v1/advance_debug',
                ngx.HTTP_POST,
                [[{
                    "enable": true,
                    "is_print_input_args": true,
                    "is_print_return_value": true,
                    "log_level":"warn",
                    "name":"hook_phase",
                    "hook_phase": {
                        "apisix": [
                            "http_access_phase",
                            "http_header_filter_phase"
                        ]
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(1.1) -- wait for debug timer start

            code, body = t('/v1/advance_debug',
                ngx.HTTP_POST,
                [[{
                    "enable": false,
                    "is_print_input_args": true,
                    "is_print_return_value": true,
                    "log_level":"warn",
                    "name":"hook_phase",
                    "hook_phase": {
                        "apisix": [
                            "http_access_phase",
                            "http_header_filter_phase"
                        ]
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(1.1) -- wait for debug timer exec

            for i = 1, 8 do

            end
            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(0.6) -- wait for sync

            local code, err, org_body
            for i = 1, 4 do
                code, err, org_body = t('/hello')
                if code > 300 then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end

            ngx.sleep(1.1) -- wait for debug timer exec

            ngx.print(org_body)
        }
    }
--- request
GET /t
--- wait: 5
--- timeout: 7
--- response_body
hello world
--- no_error_log
call require("apisix").http_access_phase() args:{}
call require("apisix").http_access_phase() return:{}
call require("apisix").http_header_filter_phase() args:{}
call require("apisix").http_header_filter_phase() return:{}



=== TEST 4: dynamic enable for plugin filter
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/v1/advance_debug',
                ngx.HTTP_POST,
                [[{
                    "enable": true,
                    "is_print_input_args": true,
                    "is_print_return_value": true,
                    "log_level":"warn",
                    "name":"hook_phase",
                    "hook_phase": {
                        "apisix.plugin": [
                            "filter"
                        ]
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(1.1) -- wait for debug timer start

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            ngx.sleep(0.6) -- wait for sync

            local code, err, org_body = t('/hello')
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.sleep(1.1) -- wait for debug timer exec

            ngx.print(org_body)
        }
    }
--- request
GET /t
--- wait: 4
--- timeout: 5
--- response_body
hello world
--- no_error_log
[error]
--- error_log
filter(): call require("apisix.plugin").filter() args:{ <1>{
filter(): call require("apisix.plugin").filter() return:{ { {
