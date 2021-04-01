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

my $out = eval { `resty -e "local s=ngx.socket.tcp();print(s.tlshandshake)"` };

if ($out !~ m/function:/) {
    plan(skip_all => "tlshandshake not patched");
} else {
    plan('no_plan');
}


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: run etcd in init phase
--- yaml_config
etcd:
  host:
    - "https://127.0.0.1:22379"
  prefix: "/apisix"
  tls:
    cert: t/certs/mtls_client.crt
    key: t/certs/mtls_client.key
    verify: false
--- init_by_lua_block
    local apisix = require("apisix")
    apisix.http_init()
    local etcd = require("apisix.core.etcd")
    assert(etcd.set("/a", "ab"))

    local res, err = etcd.get("/a")
    if not res then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.WARN, res.body.node.value)

    local res, err = etcd.delete("/a")
    if not res then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.WARN, res.status)

    local res, err = etcd.get("/a")
    if not res then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.WARN, res.status)
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- grep_error_log eval
qr/init_by_lua:\d+: \S+/
--- grep_error_log_out
init_by_lua:12: ab
init_by_lua:19: 200
init_by_lua:26: 404



=== TEST 2: run etcd in init phase (stream)
--- yaml_config
etcd:
  host:
    - "https://127.0.0.1:22379"
  prefix: "/apisix"
  tls:
    cert: t/certs/mtls_client.crt
    key: t/certs/mtls_client.key
    verify: false
--- stream_init_by_lua_block
    apisix = require("apisix")
    apisix.stream_init()
    local etcd = require("apisix.core.etcd")
    assert(etcd.set("/a", "ab"))

    local res, err = etcd.get("/a")
    if not res then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.WARN, res.body.node.value)

    local res, err = etcd.delete("/a")
    if not res then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.WARN, res.status)

    local res, err = etcd.get("/a")
    if not res then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.WARN, res.status)
--- stream_server_config
    content_by_lua_block {
        ngx.say("ok")
    }
--- stream_enable
--- grep_error_log eval
qr/init_by_lua:\d+: \S+/
--- grep_error_log_out
init_by_lua:12: ab
init_by_lua:19: 200
init_by_lua:26: 404



=== TEST 3: sync
--- extra_yaml_config
etcd:
  host:
    - "https://127.0.0.1:22379"
  prefix: "/apisix"
  tls:
    cert: t/certs/mtls_client.crt
    key: t/certs/mtls_client.key
    verify: false
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
--- request
GET /t
--- response_body
prev_index updated
--- no_error_log
[error]
--- error_log
waitdir key



=== TEST 4: sync (stream)
--- extra_yaml_config
etcd:
  host:
    - "https://127.0.0.1:22379"
  prefix: "/apisix"
  tls:
    cert: t/certs/mtls_client.crt
    key: t/certs/mtls_client.key
    verify: false
--- stream_server_config
    content_by_lua_block {
        local core = require("apisix.core")

        local sr, _ = core.config.new("/stream_routes", {
            automatic = true,
            item_schema = core.schema.stream_routes,
        })

        ngx.sleep(0.6)
        local idx = sr.prev_index

        assert(core.etcd.set("/stream_routes/1",
            {
                plugins = {
                }
            }))

        ngx.sleep(2)
        local new_idx = sr.prev_index
        if new_idx > idx then
            ngx.say("prev_index updated")
        else
            ngx.say("prev_index not update")
        end
        }
--- stream_enable
--- stream_response
prev_index updated
--- no_error_log
[error]
--- error_log
waitdir key



=== TEST 5: ssl_trusted_certificate
--- yaml_config
apisix:
  ssl:
    ssl_trusted_certificate: t/certs/mtls_ca.crt
etcd:
  host:
    - "https://127.0.0.1:22379"
  prefix: "/apisix"
  tls:
    cert: t/certs/mtls_client.crt
    key: t/certs/mtls_client.key
--- init_by_lua_block
    local apisix = require("apisix")
    apisix.http_init()
    local etcd = require("apisix.core.etcd")
    assert(etcd.set("/a", "ab"))
    local res, err = etcd.get("/a")
    if not res then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.WARN, res.body.node.value)
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- error_log
init_by_lua:11: ab
