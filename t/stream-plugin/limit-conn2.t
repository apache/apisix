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

$ENV{TEST_NGINX_REDIS_PORT} ||= 1985;

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
xrpc:
  protocols:
    - name: redis
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }


    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

worker_connections(1024);
run_tests;

__DATA__

=== TEST 1: create a stream router with limit-conn
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-conn": {
                            "conn": 2,
                            "burst": 1,
                            "default_conn_delay": 0.1,
                            "key": "$remote_port $server_addr",
                            "key_type": "var_combination"
                        }
                    },
                    "upstream": {
                        "type": "none",
                        "nodes": {
                          "127.0.0.1:6379": 1
                        }
                      },
                      "protocol": {
                        "name": "redis"
                      }
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



=== TEST 2: access the redis via proxy
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:hmset("animals", "dog", "bark", "cat", "meow")
            if not res then
                ngx.say("failed to set animals: ", err)
                return
            end
            ngx.say("hmset animals: ", res)

            local res, err = red:hmget("animals", "dog", "cat")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end
            ngx.say("hmget animals: ", res)

            ok, err = red:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        }
    }
--- response_body
hmset animals: OK
hmget animals: barkmeow
--- no_error_log
attempt to perform arithmetic on field 'request_time'
--- stream_conf_enable
