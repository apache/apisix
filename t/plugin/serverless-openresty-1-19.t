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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version =~ m/\/1.17.8/) {
    plan(skip_all => "require OpenResty 1.19+");
} else {
    plan('no_plan');
}

log_level('debug');

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: run in the balancer phase
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "balancer",
                            "functions" : ["return function(conf, ctx) ngx.req.set_header('X-SERVERLESS', ctx.balancer_ip) end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "0.0.0.0:1979": 100000,
                            "127.0.0.1:1980": 1
                        },
                        "type": "chash",
                        "key": "remote_addr"
                    },
                    "uri": "/log_request"
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



=== TEST 2: check plugin
--- request
GET /log_request
--- grep_error_log eval
qr/(proxy request to \S+|x-serverless: [\d.]+)/
--- grep_error_log_out
proxy request to 0.0.0.0:1979
proxy request to 127.0.0.1:1980
x-serverless: 127.0.0.1
--- error_log
connect() failed



=== TEST 3: exit in the balancer phase
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "balancer",
                            "functions" : ["return function(conf, ctx) ngx.exit(403) end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "0.0.0.0:1979": 100000,
                            "127.0.0.1:1980": 1
                        },
                        "type": "chash",
                        "key": "remote_addr"
                    },
                    "uri": "/log_request"
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



=== TEST 4: check plugin
--- request
GET /log_request
--- error_code: 403



=== TEST 5: ensure balancer phase run correct time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "balancer",
                            "functions" : ["return function(conf, ctx) ngx.log(ngx.WARN, 'run balancer phase with ', ctx.balancer_ip) end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "0.0.0.0:1979": 100000,
                            "127.0.0.1:1980": 1
                        },
                        "type": "chash",
                        "key": "remote_addr"
                    },
                    "uri": "/log_request"
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



=== TEST 6: check plugin
--- request
GET /log_request
--- grep_error_log eval
qr/(run balancer phase with [\d.]+)/
--- grep_error_log_out
run balancer phase with 0.0.0.0
run balancer phase with 127.0.0.1
--- error_log
connect() failed
