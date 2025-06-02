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

=== TEST 1: add serverless-pre-function with etcd delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:delete(\"/test-key\") end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t




=== TEST 2: should show warn when serverless-pre-function try to write to etcd with cli delete
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 3: add serverless-pre-function with etcd cli grant
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:grant(10) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t



=== TEST 4: should show warn when serverless-pre-function try to write to etcd with cli grant
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./




=== TEST 5: add serverless-pre-function with etcd cli setnx
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:setnx(\"/test-key\", {value = \"hello from serverless\"}) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t



=== TEST 6: should show warn when serverless-pre-function try to write to etcd with cli setnx
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 7: add serverless-pre-function with etcd cli set
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:set(\"/test-key\", {value = \"hello from serverless\"}) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t



=== TEST 8: should show warn when serverless-pre-function try to write to etcd with cli set
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 9: add serverless-pre-function with etcd cli setx
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:setx(\"/test-key\", {value = \"hello from serverless\"}) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t



=== TEST 10: should show warn when serverless-pre-function try to write to etcd with cli setx
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./




=== TEST 11: add serverless-pre-function with etcd cli rmdir
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:rmdir(\"/test-key\") end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t



=== TEST 12: should show warn when serverless-pre-function try to write to etcd with cli rmdir
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 13: add serverless-pre-function with etcd cli revoke
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:revoke(123) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t



=== TEST 14: should show warn when serverless-pre-function try to write to etcd with cli revoke
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 15: add serverless-pre-function with etcd cli keepalive
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:keepalive(123) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t



=== TEST 16: should show warn when serverless-pre-function try to write to etcd with cli keepalive
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 17: add serverless-pre-function with etcd cli get
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local etcd_cli = require(\"apisix.core.etcd\").new() etcd_cli:get(\"/my-test-key\") end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed



=== TEST 18: should not show warn when serverless-pre-function try to read from etcd with cli get
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/hello")
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- no_error_log
Data plane role should not write to etcd. This operation will be deprecated in future releases.



=== TEST 19: add serverless-pre-function with etcd function set
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local core = require(\"apisix.core\") core.etcd.set(\"/my-test-key\", {value = \"hello from serverless\"}) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed



=== TEST 20: should show warn when serverless-pre-function try to write to etcd with function set
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 21: add serverless-pre-function with etcd function atomic_set
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local core = require(\"apisix.core\") core.etcd.atomic_set(\"/my-test-key\", {value = \"hello from serverless\"}) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed



=== TEST 22: should show warn when serverless-pre-function try to write to etcd with function atomic_set
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./




=== TEST 23: add serverless-pre-function with etcd function push
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local core = require(\"apisix.core\") core.etcd.push(\"/my-test-key\", {value = \"hello from serverless\"}) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed



=== TEST 24: should show warn when serverless-pre-function try to write to etcd with function push
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./




=== TEST 25: add serverless-pre-function with etcd function delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local core = require(\"apisix.core\") core.etcd.delete(\"/my-test-key\") end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed



=== TEST 26: should show warn when serverless-pre-function try to write to etcd with function delete
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 27: add serverless-pre-function with etcd function rmdir
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local core = require(\"apisix.core\") core.etcd.rmdir(\"/my-test-key\") end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed



=== TEST 28: should show warn when serverless-pre-function try to write to etcd with function rmdir
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 29: add serverless-pre-function with etcd function keepalive
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local core = require(\"apisix.core\") core.etcd.keepalive(123) end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed



=== TEST 30: should show warn when serverless-pre-function try to write to etcd with function keepalive
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/hello')
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 31: add serverless-pre-function with etcd function get
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : [
                                "return function() local core = require(\"apisix.core\") core.etcd.get(\"/my-test-key\") end"
                            ]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
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
--- request
GET /t
--- response_body
passed



=== TEST 32: should not show warn when serverless-pre-function try to read from etcd with function get
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/hello")
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- no_error_log
Data plane role should not write to etcd. This operation will be deprecated in future releases.



=== TEST 33: should not warn when not data_plane
--- yaml_config
deployment:
  role: control_plane
  role_control_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: "/apisix"
    tls:
      verify: false
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            etcd.set("foo", "bar")
            etcd.delete("foo")
        }
    }
--- request
GET /t
--- no_error_log
Data plane role should not write to etcd. This operation will be deprecated in future releases.
