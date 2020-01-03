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
$debug_config =~ s/enable: false/enable: true/;

run_tests();

__DATA__

=== TEST 1: set route(id: 1)
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "hosts": ["foo.com", "*.bar.com"],
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



=== TEST 2: /not_found
--- request
GET /not_found
--- error_code: 404
--- response_body
{"error_msg":"failed to match any routes"}
--- no_error_log
[error]



=== TEST 3: phases log
--- debug_config eval: $::debug_config
--- request
GET /hello
--- more_headers
Host: foo.com
--- response_body
hello world
--- no_error_log
[error]
--- error_log
call require("apisix").http_header_filter_phase() args:{}
call require("apisix").http_header_filter_phase() return:{}
call require("apisix").http_body_filter_phase() args:{}
call require("apisix").http_body_filter_phase() return:{}
call require("apisix").http_log_phase() args:{}
call require("apisix").http_log_phase() return:{}



=== TEST 4: plugin filter log
--- debug_config
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
--- request
GET /hello
--- more_headers
Host: foo.com
--- response_body
hello world
--- no_error_log
[error]
--- error_log
filter(): call require("apisix.plugin").filter() args:[{
filter(): call require("apisix.plugin").filter() return:[[{
