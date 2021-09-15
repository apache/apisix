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

sub read_file($) {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $debug_config = read_file("conf/debug.yaml");
$debug_config =~ s/http:\n  enable: false/http:\n  enable: true/;

run_tests();

__DATA__

=== TEST 1: dynamic enable
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
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

            local headers = {}
            headers["X-APISIX-Dynamic-Debug"] = ""
            local code, body = t('/hello',
                ngx.HTTP_GET,
                "",
                nil,
                headers
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- wait: 2
--- timeout: 4
--- response_body
passed
--- error_log
call require("apisix").http_access_phase() return:{}
call require("apisix").http_header_filter_phase() args:{}
call require("apisix").http_header_filter_phase() return:{}
call require("apisix").http_body_filter_phase() args:{}
call require("apisix").http_body_filter_phase() return:{}
call require("apisix").http_log_phase() args:{}
call require("apisix").http_log_phase() return:{}
--- no_error_log
call require("apisix").http_access_phase() args:{}



=== TEST 2: dynamic enable by per request and disable after handle request
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uris": ["/hello","/hello1"],
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
            local http = require "resty.http"
            local httpc = http.new()
            local headers = {}
            headers["X-APISIX-Dynamic-Debug"] = ""
            local uri1 = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello1"
            local res, err = httpc:request_uri(uri1, {method = "GET", headers = headers})
            if not res then
                ngx.say(err)
                return
            end

            local uri2 = "http://127.0.0.1:" .. ngx.var.server_port
                         .. "/hello"
            res, err = httpc:request_uri(uri2)
            if not res then
                ngx.say(err)
                return
            end

            ngx.print(res.body)
        }
    }
--- request
GET /t
--- response_body
hello world
--- error_log eval
[qr/call\srequire\(\"apisix\"\).http_access_phase\(\)\sreturn\:\{\}.*GET\s\/hello1\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_header_filter_phase\(\)\sargs\:\{\}.*GET\s\/hello1\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_header_filter_phase\(\)\sreturn\:\{\}.*GET\s\/hello1\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_body_filter_phase\(\)\sargs\:\{\}.*GET\s\/hello1\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_body_filter_phase\(\)\sreturn\:\{\}.*GET\s\/hello1\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_log_phase\(\)\sargs\:\{\}.*GET\s\/hello1\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_log_phase\(\)\sreturn\:\{\}.*GET\s\/hello1\sHTTP\/1.1/]
--- no_error_log eval
[qr/call\srequire\(\"apisix\"\).http_access_phase\(\)\sargs\:\{\}.*GET\s\/hello\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_access_phase\(\)\sreturn\:\{\}.*GET\s\/hello\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_header_filter_phase\(\)\sargs\:\{\}.*GET\s\/hello\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_header_filter_phase\(\)\sreturn\:\{\}.*GET\s\/hello\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_body_filter_phase\(\)\sargs\:\{\}.*GET\s\/hello\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_body_filter_phase\(\)\sreturn\:\{\}.*GET\s\/hello\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_log_phase\(\)\sargs\:\{\}.*GET\s\/hello\sHTTP\/1.1/,
qr/call\srequire\(\"apisix\"\).http_log_phase\(\)\sreturn\:\{\}.*GET\s\/hello\sHTTP\/1.1/]



=== TEST 3: error dynamic enable header
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
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

            local headers = {}
            headers["X-APISIX-Dynamic-Error"] = ""
            local code, body = t('/hello',
                ngx.HTTP_GET,
                "",
                nil,
                headers
            )
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- wait: 2
--- timeout: 4
--- response_body
passed
--- no_error_log
call require("apisix").http_header_filter_phase() args:{}
call require("apisix").http_header_filter_phase() return:{}
call require("apisix").http_body_filter_phase() args:{}
call require("apisix").http_body_filter_phase() return:{}
call require("apisix").http_log_phase() args:{}
call require("apisix").http_log_phase() return:{}



=== TEST 4: plugin filter log
--- debug_config
http:
  enable: true         # enable or disable this feature
  enable_header_name: X-APISIX-Dynamic-Debug # the header name of dynamic enable
hook_conf:
  enable: true                  # enable or disable this feature
  name: hook_test               # the name of module and function list
  log_level: warn               # log level
  is_print_input_args: true     # print the input arguments
  is_print_return_value: true   # print the return value

hook_test:                      # module and function list, name: hook_test
    apisix.plugin:              # required module name
    - filter                    # function name

#END
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
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

            local headers = {}
            headers["X-APISIX-Dynamic-Debug"] = ""  -- has the header name of dynamic debug
            local code, body = t('/hello',
                ngx.HTTP_GET,
                "",
                nil,
                headers
            )

            ngx.sleep(1.1)
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- wait: 2
--- timeout: 3
--- response_body
passed
--- no_error_log
[error]
--- error_log
filter(): call require("apisix.plugin").filter() args:{
filter(): call require("apisix.plugin").filter() return:{



=== TEST 5: multiple requests, only output logs of the request with enable_header_name
--- debug_config
http:
  enable: true
  enable_header_name: X-APISIX-Dynamic-Debug
hook_conf:
  enable: false
  name: hook_test
  log_level: warn
  is_print_input_args: true
  is_print_return_value: true
hook_test:
    apisix.plugin:
    - filter
#END
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/mysleep*",
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

            local res, err
            local http = require "resty.http"
            local httpc = http.new()
            for i = 1, 3 do
                if i == 1 then
                    local headers = {}
                    headers["X-APISIX-Dynamic-Debug"] = ""
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port
                                .. "/mysleep?seconds=1"
                    local res, err = httpc:request_uri(uri, {method = "GET", headers = headers})
                    if not res then
                        ngx.say(err)
                        return
                    end
                else
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port
                                .. "/mysleep?seconds=0.1"
                    res, err = httpc:request_uri(uri)
                    if not res then
                        ngx.say(err)
                        return
                    end
                end
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_log eval
qr/call\srequire\(\"apisix.plugin\"\).filter\(\)\sreturn.*GET\s\/mysleep\?seconds\=1\sHTTP\/1.1/
--- no_error_log eval
qr/call\srequire\(\"apisix.plugin\"\).filter\(\)\sreturn.*GET\s\/mysleep\?seconds\=0.1\sHTTP\/1.1/
