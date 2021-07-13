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

repeat_each(1);
log_level('debug');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: bad pool size
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1983": 1
                    },
                    "keepalive_pool": {
                        "size": 0
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"keepalive_pool\" validation failed: property \"size\" validation failed: expected 0 to be greater than 1"}



=== TEST 2: set route/upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "keepalive_pool": {
                        "size": 4,
                        "idle_timeout": 8,
                        "requests": 16
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri":"/hello",
                    "upstream_id": 1
                }]])
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }



=== TEST 3: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            for i = 1, 3 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.print(res.body)
            end
        }
    }
--- response_body
hello world
hello world
hello world
--- grep_error_log eval
qr/lua balancer: keepalive .*/
--- grep_error_log_out eval
qr/^lua balancer: keepalive create pool, crc32: \S+, size: 4
lua balancer: keepalive no free connection, cpool: \S+
lua balancer: keepalive saving connection \S+, cpool: \S+, connections: 1
lua balancer: keepalive reusing connection \S+, requests: 1, cpool: \S+
lua balancer: keepalive saving connection \S+, cpool: \S+, connections: 1
lua balancer: keepalive reusing connection \S+, requests: 2, cpool: \S+
lua balancer: keepalive saving connection \S+, cpool: \S+, connections: 1
$/



=== TEST 4: only reuse one time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "keepalive_pool": {
                        "size": 1,
                        "idle_timeout": 8,
                        "requests": 2
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }



=== TEST 5: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            for i = 1, 3 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.print(res.body)
            end
        }
    }
--- response_body
hello world
hello world
hello world
--- grep_error_log eval
qr/lua balancer: keepalive .*/
--- grep_error_log_out eval
qr/^lua balancer: keepalive create pool, crc32: \S+, size: 1
lua balancer: keepalive no free connection, cpool: \S+
lua balancer: keepalive saving connection \S+, cpool: \S+, connections: 1
lua balancer: keepalive reusing connection \S+, requests: 1, cpool: \S+
lua balancer: keepalive not saving connection \S+, cpool: \S+, connections: 0
lua balancer: keepalive free pool \S+, crc32: \S+
lua balancer: keepalive create pool, crc32: \S+, size: 1
lua balancer: keepalive no free connection, cpool: \S+
lua balancer: keepalive saving connection \S+, cpool: \S+, connections: 1
$/
