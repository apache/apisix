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

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (! $block->request) {
        $block->set_value("request", "GET /t");
    }
});


run_tests;

__DATA__

=== TEST 1: prepare
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "host": "$host",
                        "client_ip": "$remote_addr"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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
--- response_body
passed



=== TEST 2: cache file
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            assert(io.open("file.log", 'r'))
            os.remove("file.log")
            local code = t("/hello", ngx.HTTP_GET)
            local _, err = io.open("file.log", 'r')
            ngx.say(err)
        }
    }
--- response_body
file.log: No such file or directory



=== TEST 3: reopen file
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            assert(io.open("file.log", 'r'))
            os.remove("file.log")
            ngx.sleep(0.01) -- make sure last reopen file is expired

            local process = require "ngx.process"
            local resty_signal = require "resty.signal"
            local pid = process.get_master_pid()

            local ok, err = resty_signal.kill(pid, "USR1")
            if not ok then
                ngx.log(ngx.ERR, "failed to kill process of pid ", pid, ": ", err)
                return
            end

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            -- file is reopened
            local fd, err = io.open("file.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file.log, error info: ", err)
                return
            end

            msg = fd:read()

            local new_msg = core.json.decode(msg)
            if new_msg.client_ip == '127.0.0.1' and new_msg.route_id == '1'
                and new_msg.host == '127.0.0.1'
            then
                msg = "write file log success"
                ngx.status = code
                ngx.say(msg)
            end

            os.remove("file.log")
            local code = t("/hello", ngx.HTTP_GET)
            local _, err = io.open("file.log", 'r')
            ngx.say(err)
        }
    }
--- response_body
write file log success
file.log: No such file or directory
--- grep_error_log eval
qr/reopen cached log file: file.log/
--- grep_error_log_out
reopen cached log file: file.log
