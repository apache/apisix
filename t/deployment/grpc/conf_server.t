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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: sync in https
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test

            local consumers, _ = core.config.new("/consumers", {
                automatic = true,
                item_schema = core.schema.consumer,
            })

            ngx.sleep(0.6)
            local idx = consumers.prev_index

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jobs",
                    "plugins": {
                        "basic-auth": {
                            "username": "jobs",
                            "password": "678901"
                        }
                    }
                }]])

            ngx.sleep(2)
            local new_idx = consumers.prev_index
            if new_idx > idx then
                ngx.say("prev_index updated")
            else
                ngx.say("prev_index not update")
            end
        }
    }
--- response_body
prev_index updated
--- yaml_config
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    admin:
        admin_key: ~
    etcd:
        use_grpc: true
        prefix: "/apisix"
        host:
            - https://127.0.0.1:12379
        tls:
            verify: false



=== TEST 2: mix ip & domain
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            assert(etcd.set("/apisix/test", "foo"))
            local res = assert(etcd.get("/apisix/test"))
            ngx.say(res.body.node.value)
        }
    }
--- yaml_config
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        use_grpc: true
        prefix: "/apisix"
        host:
            - http://127.0.0.2:2379
            - http://localhost:2379
            - http://[::1]:2379
--- response_body
foo



=== TEST 3: check default SNI
--- http_config
server {
    listen 12345 http2 ssl;
    ssl_certificate             cert/apisix.crt;
    ssl_certificate_key         cert/apisix.key;

    ssl_certificate_by_lua_block {
        local ngx_ssl = require "ngx.ssl"
        ngx.log(ngx.WARN, "Receive SNI: ", ngx_ssl.server_name())
    }

    location / {
        grpc_pass grpc://127.0.0.1:2379;
    }
}
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            assert(etcd.set("/apisix/test", "foo"))
            local res = assert(etcd.get("/apisix/test"))
            ngx.say(res.body.node.value)
        }
    }
--- response_body
foo
--- yaml_config
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        use_grpc: true
        prefix: "/apisix"
        host:
            - https://127.0.0.1:12379
            - https://localhost:12345
        timeout: 1
        tls:
            verify: false
--- error_log
Receive SNI: localhost
