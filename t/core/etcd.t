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

=== TEST 1: delete test data if exists
--- config
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /delete
--- ignore_response



=== TEST 2: (add + update + delete) *2 (same uri)
--- config
    location /add {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 2
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /add", "GET /hello", "GET /update", "GET /hello", "GET /delete", "GET /hello",
"GET /add", "GET /hello", "GET /update", "GET /hello", "GET /delete", "GET /hello"]
--- more_headers
Host: foo.com
--- error_code eval
[201, 200, 200, 200, 200, 404, 201, 200, 200, 200, 200, 404]
--- response_body eval
["passed\n", "hello world\n", "passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n",
"passed\n", "hello world\n", "passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n"]
--- timeout: 5



=== TEST 3: add + update + delete + add + update + delete (different uris)
--- config
    location /add {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 2
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/status"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /add2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello_chunked"
                }]],
                nil
                )
                ngx.sleep(1)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{

                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 2
                        },
                        "type": "roundrobin"
                    },
                    "host": "foo.com",
                    "uri": "/hello1"
                }]],
                nil
                )
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.status = code
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /add", "GET /hello", "GET /update", "GET /hello", "GET /status", "GET /delete", "GET /status",
"GET /add2", "GET /hello_chunked", "GET /update2", "GET /hello_chunked", "GET /hello1", "GET /delete", "GET /hello1"]
--- more_headers
Host: foo.com
--- error_code eval
[201, 200, 200, 404, 200, 200, 404, 201, 200, 200, 404, 200, 200, 404]
--- response_body eval
["passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n", "ok\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n",
"passed\n", "hello world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n", "hello1 world\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n"]
--- timeout: 5



=== TEST 4: add*50 + update*50 + delete*50
--- config
    location /add {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 1, 25 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path,
                    ngx.HTTP_PUT,
                    string.format('{"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "foo.com","uri": "/print_uri_%s"}', tostring(i)),
                    nil
                )
            end
            ngx.sleep(2)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /add2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 26, 50 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path,
                    ngx.HTTP_PUT,
                    string.format('{"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "foo.com","uri": "/print_uri_%s"}', tostring(i)),
                    nil
                )
            end
            ngx.sleep(2)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 1, 25 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path,
                    ngx.HTTP_PUT,
                    string.format('{"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "foo.com","uri": "/print_uri_%s"}', tostring(i)),
                    nil
                    )
            end
            ngx.sleep(2)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /update2 {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 26, 50 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path,
                    ngx.HTTP_PUT,
                    string.format('{"upstream": {"nodes": {"127.0.0.1:1980": 1},"type": "roundrobin"},"host": "foo.com","uri": "/print_uri_%s"}', tostring(i)),
                    nil
                    )
            end
            ngx.sleep(2)
            ngx.status = code
            ngx.say(body)
        }
    }
    location /delete {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local path = ""
            local code, body
            for i = 1, 50 do
                path = '/apisix/admin/routes/' .. tostring(i)
                code, body = t(path, ngx.HTTP_DELETE)
            end
            ngx.status = code
            ngx.say(body)
        }
    }
--- pipelined_requests eval
["GET /add", "GET /print_uri_20", "GET /add2", "GET /print_uri_36", "GET /update", "GET /print_uri_12", "GET /delete", "GET /print_uri_12"]
--- more_headers
Host: foo.com
--- error_code eval
[201, 200, 201, 200, 200, 200, 200, 404]
--- response_body eval
["passed\n", "/print_uri_20\n", "passed\n", "/print_uri_36\n", "passed\n", "/print_uri_12\n", "passed\n", "{\"error_msg\":\"404 Route Not Found\"}\n"]
--- timeout: 20



=== TEST 5: get single
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            assert(etcd.set("/ab", "ab"))
            local res, err = etcd.get("/a")
            ngx.status = res.status
        }
    }
--- request
GET /t
--- error_code: 404



=== TEST 6: get prefix
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            assert(etcd.set("/ab", "ab"))
            local res, err = etcd.get("/a", true)
            assert(err == nil)
            assert(#res.body.list == 1)
            ngx.status = res.status
            ngx.say(res.body.list[1].value)
        }
    }
--- request
GET /t
--- response_body
ab



=== TEST 7: run etcd in init phase
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
qr/init_by_lua.*: \S+/
--- grep_error_log_out eval
qr{init_by_lua.* ab
init_by_lua.* 200
init_by_lua.* 404}



=== TEST 8: list multiple kv, get prefix
--- config
    location /t {
        content_by_lua_block {
            local etcd = require("apisix.core.etcd")
            assert(etcd.set("/ab", "ab"))
            assert(etcd.set("/abc", "abc"))
            -- get prefix
            local res, err = etcd.get("/a", true)
            assert(err == nil)
            assert(#res.body.list == 2)
            ngx.status = res.status
            ngx.say(res.body.list[1].value)
            ngx.say(res.body.list[2].value)
        }
    }
--- request
GET /t
--- response_body
ab
abc



=== TEST 9: should warn when data_plane + etcd
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
            local etcd = require("apisix.core.etcd")
            etcd.set("foo", "bar")
            etcd.delete("foo")
        }
    }
--- request
GET /t
--- error_log eval
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 10: should not warn when data_plane + yaml
--- yaml_config
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
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
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./



=== TEST 11: should not warn when not data_plane
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
qr/Data plane role should not write to etcd. This operation will be deprecated in future releases./
