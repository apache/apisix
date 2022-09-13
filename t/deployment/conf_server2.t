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

=== TEST 1: health check, ensure unhealthy endpoint is skipped
--- http_config
server {
    listen 12345;
    location / {
        access_by_lua_block {
            if package.loaded.start_to_fail then
                ngx.exit(502)
            end
        }
        proxy_pass http://127.0.0.1:2379;
    }
}
--- yaml_config
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        prefix: "/apisix"
        host:
            - http://127.0.0.1:2379
            - http://localhost:12345
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            package.loaded.start_to_fail = true
            for i = 1, 7 do
                assert(etcd.set("/apisix/test", "foo"))
            end
            package.loaded.start_to_fail = nil
            ngx.say('OK')
        }
    }
--- response_body
OK
--- error_log
report failure, endpoint: localhost:12345
endpoint localhost:12345 is unhealthy, skipped



=== TEST 2: health check, all endpoints are unhealthy
--- http_config
server {
    listen 12345;
    location / {
        access_by_lua_block {
            if package.loaded.start_to_fail then
                ngx.exit(502)
            end
        }
        proxy_pass http://127.0.0.1:2379;
    }
}
--- yaml_config
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        prefix: "/apisix"
        host:
            - http://localhost:12345
            - http://127.0.0.1:12345
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            package.loaded.start_to_fail = true
            for i = 1, 6 do
                etcd.set("/apisix/test", "foo")
            end
            package.loaded.start_to_fail = nil
            local _, err = etcd.set("/apisix/test", "foo")
            ngx.say(err)
        }
    }
--- response_body
invalid response code: 503
--- error_log
endpoint localhost:12345 is unhealthy, skipped
endpoint 127.0.0.1:12345 is unhealthy, skipped



=== TEST 3: health check, all endpoints recover from unhealthy
--- http_config
server {
    listen 12345;
    location / {
        access_by_lua_block {
            if package.loaded.start_to_fail then
                ngx.exit(502)
            end
        }
        proxy_pass http://127.0.0.1:2379;
    }
}
--- yaml_config
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    etcd:
        health_check_timeout: 1
        prefix: "/apisix"
        host:
            - http://localhost:12345
            - http://127.0.0.1:12345
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            package.loaded.start_to_fail = true
            for i = 1, 6 do
                etcd.set("/apisix/test", "foo")
            end
            package.loaded.start_to_fail = nil
            ngx.sleep(1.2)
            local res, err = etcd.set("/apisix/test", "foo")
            ngx.say(err or res.body.node.value)
        }
    }
--- response_body
foo
--- error_log
endpoint localhost:12345 is unhealthy, skipped
endpoint 127.0.0.1:12345 is unhealthy, skipped
