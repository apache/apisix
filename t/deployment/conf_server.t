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

worker_connections(256);

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
        prefix: "/apisix"
        host:
            - http://127.0.0.2:2379
            - http://localhost:2379
            - http://[::1]:2379
--- error_log
dns resolve localhost, result:
--- response_body
foo



=== TEST 3: resolve domain, result changed
--- extra_init_by_lua
    local resolver = require("apisix.core.resolver")
    local old_f = resolver.parse_domain
    local counter = 0
    resolver.parse_domain = function (domain)
        if domain == "localhost" then
            counter = counter + 1
            if counter % 2 == 0 then
                return "127.0.0.2"
            else
                return "127.0.0.3"
            end
        else
            return old_f(domain)
        end
    end
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
        prefix: "/apisix"
        host:
            # use localhost so the connection is OK in the situation that the DNS
            # resolve is not done in APISIX
            - http://localhost:2379
--- response_body
foo
--- error_log
localhost is resolved to: 127.0.0.3
localhost is resolved to: 127.0.0.2



=== TEST 4: update balancer if the DNS result changed
--- extra_init_by_lua
    local etcd = require("apisix.core.etcd")
    etcd.get_etcd_syncer = function ()
        return etcd.new()
    end

    local resolver = require("apisix.core.resolver")
    local old_f = resolver.parse_domain
    package.loaded.counter = 0
    resolver.parse_domain = function (domain)
        if domain == "x.com" then
            local counter = package.loaded.counter
            package.loaded.counter = counter + 1
            if counter % 2 == 0 then
                return "127.0.0.2"
            else
                return "127.0.0.3"
            end
        else
            return old_f(domain)
        end
    end

    local picker = require("apisix.balancer.least_conn")
    package.loaded.n_picker = 0
    local old_f = picker.new
    picker.new = function (nodes, upstream)
        package.loaded.n_picker = package.loaded.n_picker + 1
        return old_f(nodes, upstream)
    end
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            assert(etcd.set("/apisix/test", "foo"))
            local res = assert(etcd.get("/apisix/test"))
            ngx.say(res.body.node.value)
            local counter = package.loaded.counter
            local n_picker = package.loaded.n_picker
            if counter == n_picker then
                ngx.say("OK")
            else
                ngx.say(counter, " ", n_picker)
            end
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
            - http://x.com:2379
--- response_body
foo
OK
--- error_log
x.com is resolved to: 127.0.0.3
x.com is resolved to: 127.0.0.2



=== TEST 5: retry
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
        prefix: "/apisix"
        host:
            - http://127.0.0.1:1979
            - http://[::1]:1979
            - http://localhost:2379
--- error_log
connect() failed
--- response_body
foo



=== TEST 6: check default SNI
--- http_config
server {
    listen 12345 ssl;
    ssl_certificate             cert/apisix.crt;
    ssl_certificate_key         cert/apisix.key;

    ssl_certificate_by_lua_block {
        local ngx_ssl = require "ngx.ssl"
        ngx.log(ngx.WARN, "Receive SNI: ", ngx_ssl.server_name())
    }

    location / {
        proxy_pass http://127.0.0.1:2379;
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
        prefix: "/apisix"
        host:
            - https://127.0.0.1:12379
            - https://localhost:12345
        tls:
            verify: false
--- error_log
Receive SNI: localhost



=== TEST 7: check configured SNI
--- http_config
server {
    listen 12345 ssl;
    ssl_certificate             cert/apisix.crt;
    ssl_certificate_key         cert/apisix.key;

    ssl_certificate_by_lua_block {
        local ngx_ssl = require "ngx.ssl"
        ngx.log(ngx.WARN, "Receive SNI: ", ngx_ssl.server_name())
    }

    location / {
        proxy_pass http://127.0.0.1:2379;
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
        prefix: "/apisix"
        host:
            - https://127.0.0.1:12379
            - https://127.0.0.1:12345
        tls:
            verify: false
            sni: "x.com"
--- error_log
Receive SNI: x.com



=== TEST 8: check Host header
--- http_config
server {
    listen 12345;
    location / {
        access_by_lua_block {
            ngx.log(ngx.WARN, "Receive Host: ", ngx.var.http_host)
        }
        proxy_pass http://127.0.0.1:2379;
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
        prefix: "/apisix"
        host:
            - http://127.0.0.1:12345
            - http://localhost:12345
--- error_log
Receive Host: localhost
Receive Host: 127.0.0.1



=== TEST 9: check Host header after retry
--- http_config
server {
    listen 12345;
    location / {
        access_by_lua_block {
            ngx.log(ngx.WARN, "Receive Host: ", ngx.var.http_host)
        }
        proxy_pass http://127.0.0.1:2379;
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
        prefix: "/apisix"
        host:
            - http://127.0.0.1:1979
            - http://localhost:12345
--- error_log
Receive Host: localhost



=== TEST 10: default timeout
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            local etcd_cli = require("resty.etcd")
            local f = etcd_cli.new
            local timeout
            etcd_cli.new = function(conf)
                timeout = conf.timeout
                return f(conf)
            end
            etcd.new()
            ngx.say(timeout)
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
--- response_body
30



=== TEST 11: ipv6
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
        prefix: "/apisix"
        host:
            - http://[::1]:2379
