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
no_long_string();
no_root_location();
log_level("info");

run_tests;

__DATA__

=== TEST 1: wrong etcd port
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    prefix: "/apisix"
    host:
      - "http://127.0.0.1:7777"  -- wrong etcd port
    timeout: 1
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(8)
            ngx.say(body)
        }
    }
--- timeout: 12
--- request
GET /t
--- grep_error_log eval
qr{connection refused}
--- grep_error_log_out eval
qr/(connection refused){1,}/



=== TEST 2: originate TLS connection to etcd cluster without TLS configuration
--- yaml_config
apisix:
  node_listen: 1984
  ssl:
    ssl_trusted_certificate: t/servroot/conf/cert/etcd.pem
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "https://127.0.0.1:2379"
--- extra_init_by_lua
local health_check = require("resty.etcd.health_check")
health_check.get_target_status = function()
    return true
end
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(4)
            ngx.say("ok")
        }
    }
--- timeout: 5
--- request
GET /t
--- grep_error_log chop
peer closed connection in SSL handshake
--- grep_error_log_out eval
qr/(peer closed connection in SSL handshake){1,}/



=== TEST 3: originate plain connection to etcd cluster which enables TLS
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:12379"
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(4)
            ngx.say("ok")
        }
    }
--- timeout: 5
--- request
GET /t
--- grep_error_log chop
closed
--- grep_error_log_out eval
qr/(closed){1,}/



=== TEST 4: set route(id: 1) to etcd cluster with TLS
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
  etcd:
    host:
      - "https://127.0.0.1:12379"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]]
            )

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: get route(id: 1) from etcd cluster with TLS
--- yaml_config
apisix:
  node_listen: 1984
  admin_key: null
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: ~
  etcd:
    host:
      - "https://127.0.0.1:12379"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_GET,
                 nil
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: ensure only one auth request per subsystem for all the etcd sync
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:1980" -- fake server port
    timeout: 1
    user: root                    # root username for etcd
    password: 5tHkHhYkjr6cQY      # root password for etcd
--- extra_init_by_lua
local health_check = require("resty.etcd.health_check")
health_check.get_target_status = function()
    return true
end
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/etcd auth failed/
--- grep_error_log_out
etcd auth failed
etcd auth failed
etcd auth failed



=== TEST 7: ensure add prefix automatically for _M.getkey
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")

            local config = core.config.new()
            local res = config:getkey("/routes/")
            if res and res.status == 200 and res.body
               and res.body.count and tonumber(res.body.count) >= 1 then
                ngx.say("passed")
              else
                ngx.say("failed")
            end

            local res = config:getkey("/phantomkey")
            if res and res.status == 404 then
                ngx.say("passed")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
passed
passed



=== TEST 8: Test ETCD health check mode switch during APISIX startup
--- config
    location /t {
        content_by_lua_block {
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/healthy check use \S+ \w+/
--- grep_error_log_out eval
qr/healthy check use round robin
(healthy check use ngx.shared dict){1,}/



=== TEST 9: last_err can be nil when the reconnection is successful
--- config
    location /t {
        content_by_lua_block {
            local config_etcd = require("apisix.core.config_etcd")
            local count = 0
            config_etcd.inject_sync_data(function()
                if count % 2 == 0 then
                    count = count + 1
                    return nil, "has no healthy etcd endpoint available"
                else
                    return true
                end
            end)
            config_etcd.test_automatic_fetch(false, {
                running = true,
                resync_delay = 1,
            })
            ngx.say("passed")
        }
    }
--- request
GET /t
--- error_log
reconnected to etcd
--- response_body
passed



=== TEST 10: reloaded data may be in res.body.node (special kvs structure)
--- yaml_config
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    admin:
        admin_key: null
--- config
    location /t {
        content_by_lua_block {
            local config_etcd = require("apisix.core.config_etcd")
            local etcd_cli = {}
            function etcd_cli.readdir()
                return {
                    status = 200,
                    headers = {},
                    body = {
                        header = {revision = 1},
                        kvs = {{key = "foo", value = "bar"}},
                    }
                }
            end
            config_etcd.test_sync_data({
                etcd_cli = etcd_cli,
                key = "fake",
                single_item = true,
                -- need_reload because something wrong happened before
                need_reload = true,
                upgrade_version = function() end,
                conf_version = 1,
            })
        }
    }
--- request
GET /t
--- log_level: debug
--- grep_error_log eval
qr/readdir key: fake res: .+/
--- grep_error_log_out eval
qr/readdir key: fake res: \[\{("value":"bar","key":"foo"|"key":"foo","value":"bar")\}\]/
--- wait: 1
--- no_error_log
[error]



=== TEST 11: reloaded data may be in res.body.node (admin_api_version is v2)
--- yaml_config
deployment:
    role: traditional
    role_traditional:
        config_provider: etcd
    admin:
        admin_key: null
        admin_api_version: v2
--- config
    location /t {
        content_by_lua_block {
            local config_etcd = require("apisix.core.config_etcd")
            local etcd_cli = {}
            function etcd_cli.readdir()
                return {
                    status = 200,
                    headers = {},
                    body = {
                        header = {revision = 1},
                        kvs = {
                            {key = "/foo"},
                            {key = "/foo/bar", value = {"bar"}}
                        },
                    }
                }
            end
            config_etcd.test_sync_data({
                etcd_cli = etcd_cli,
                key = "fake",
                -- need_reload because something wrong happened before
                need_reload = true,
                upgrade_version = function() end,
                conf_version = 1,
            })
        }
    }
--- request
GET /t
--- log_level: debug
--- grep_error_log eval
qr/readdir key: fake res: .+/
--- grep_error_log_out eval
qr/readdir key: fake res: \{.*"nodes":\[\{.*"value":\["bar"\].*\}\].*\}/
--- wait: 1
--- no_error_log
[error]



=== TEST 12: test route with special character "-"
--- yaml_config
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
  etcd:
    prefix: "/apisix-test"
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)

            local http = require "resty.http"
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)

            -- hit
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                method = "GET"
            })

            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.print(res.body)

            -- delete route
            code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            -- hit
            res, err = httpc:request_uri(uri, {
                method = "GET"
            })

            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- response_body
passed
hello world
passed
{"error_msg":"404 Route Not Found"}



=== TEST 13: the main watcher should be initialised once
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
  etcd:
    host:
      - "http://127.0.0.1:2379"
    watch_timeout: 1
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/main etcd watcher initialised, revision=/
--- grep_error_log_out
main etcd watcher initialised, revision=
main etcd watcher initialised, revision=
