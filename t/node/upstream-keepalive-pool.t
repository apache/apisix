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
{"error_msg":"invalid configuration: property \"keepalive_pool\" validation failed: property \"size\" validation failed: expected 0 to be at least 1"}



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



=== TEST 6: set upstream without keepalive_pool
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
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end
        }
    }



=== TEST 7: should not override default value
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
qr/^lua balancer: keepalive create pool, crc32: \S+, size: 320
lua balancer: keepalive no free connection, cpool: \S+
lua balancer: keepalive saving connection \S+, cpool: \S+, connections: 1
lua balancer: keepalive reusing connection \S+, requests: 1, cpool: \S+
lua balancer: keepalive saving connection \S+, cpool: \S+, connections: 1
lua balancer: keepalive reusing connection \S+, requests: 2, cpool: \S+
lua balancer: keepalive saving connection \S+, cpool: \S+, connections: 1
$/



=== TEST 8: upstreams with different client cert
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local test = require("lib.test_admin").test
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local ssl_cert2 = t.read_file("t/certs/apisix.crt")
            local ssl_key2 = t.read_file("t/certs/apisix.key")

            local code, body = test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1983": 1
                    },
                    "keepalive_pool": {
                        "size": 4
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = {
                scheme = "https",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1983"] = 1,
                },
                tls = {
                    client_cert = ssl_cert,
                    client_key = ssl_key,
                },
                keepalive_pool = {
                    size = 8
                }
            }
            local code, body = test('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = {
                scheme = "https",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1983"] = 1,
                },
                tls = {
                    client_cert = ssl_cert2,
                    client_key = ssl_key2,
                },
                keepalive_pool = {
                    size = 16
                }
            }
            local code, body = test('/apisix/admin/upstreams/3',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            for i = 1, 3 do
                local code, body = test('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "uri":"/hello/]] .. i .. [[",
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/hello"
                            }
                        },
                        "upstream_id": ]] .. i .. [[
                    }]])
                if code >= 300 then
                    ngx.status = code
                    ngx.print(body)
                    return
                end
            end
        }
    }
--- response_body



=== TEST 9: hit
--- upstream_server_config
    ssl_client_certificate ../../certs/mtls_ca.crt;
    ssl_verify_client on;
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            for i = 1, 12 do
                local idx = (i % 3) + 1
                local httpc = http.new()
                local res, err = httpc:request_uri(uri .. "/hello/" .. idx)
                if not res then
                    ngx.say(err)
                    return
                end

                if idx == 2 then
                    assert(res.status == 200)
                else
                    assert(res.status == 400)
                end
            end
        }
    }



=== TEST 10: upstreams with different client cert (without pool)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local test = require("lib.test_admin").test
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")
            local ssl_cert2 = t.read_file("t/certs/apisix.crt")
            local ssl_key2 = t.read_file("t/certs/apisix.key")

            local code, body = test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1983": 1
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = {
                scheme = "https",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1983"] = 1,
                },
                tls = {
                    client_cert = ssl_cert,
                    client_key = ssl_key,
                }
            }
            local code, body = test('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = {
                scheme = "https",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1983"] = 1,
                },
                tls = {
                    client_cert = ssl_cert2,
                    client_key = ssl_key2,
                }
            }
            local code, body = test('/apisix/admin/upstreams/3',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            for i = 1, 3 do
                local code, body = test('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "uri":"/hello/]] .. i .. [[",
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/hello"
                            }
                        },
                        "upstream_id": ]] .. i .. [[
                    }]])
                if code >= 300 then
                    ngx.status = code
                    ngx.print(body)
                    return
                end
            end
        }
    }
--- response_body



=== TEST 11: hit
--- upstream_server_config
    ssl_client_certificate ../../certs/mtls_ca.crt;
    ssl_verify_client on;
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            for i = 1, 12 do
                local idx = (i % 3) + 1
                local httpc = http.new()
                local res, err = httpc:request_uri(uri .. "/hello/" .. idx)
                if not res then
                    ngx.say(err)
                    return
                end

                if idx == 2 then
                    assert(res.status == 200)
                else
                    assert(res.status == 400)
                end
            end
        }
    }



=== TEST 12: upstreams with different SNI
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local test = require("lib.test_admin").test
            local json = require("toolkit.json")

            local code, body = test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1983": 1
                    },
                    "pass_host": "rewrite",
                    "upstream_host": "a.com",
                    "keepalive_pool": {
                        "size": 4
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = {
                scheme = "https",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1983"] = 1,
                },
                pass_host = "rewrite",
                upstream_host = "b.com",
                keepalive_pool = {
                    size = 8
                }
            }
            local code, body = test('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            for i = 1, 2 do
                local code, body = test('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "uri":"/hello/]] .. i .. [[",
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/hello"
                            }
                        },
                        "upstream_id": ]] .. i .. [[
                    }]])
                if code >= 300 then
                    ngx.status = code
                    ngx.print(body)
                    return
                end
            end
        }
    }
--- response_body



=== TEST 13: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            for i = 1, 4 do
                local idx = i % 2 + 1
                local httpc = http.new()
                local res, err = httpc:request_uri(uri .. "/hello/" .. idx)
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.print(res.body)
            end
        }
    }
--- grep_error_log eval
qr/lua balancer: keepalive create pool, .*/
--- grep_error_log_out eval
qr/^lua balancer: keepalive create pool, crc32: \S+, size: 8
lua balancer: keepalive create pool, crc32: \S+, size: 4
$/



=== TEST 14: upstreams with SNI, then without SNI
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local test = require("lib.test_admin").test
            local json = require("toolkit.json")

            local code, body = test('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "scheme": "https",
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1983": 1
                    },
                    "pass_host": "rewrite",
                    "upstream_host": "a.com",
                    "keepalive_pool": {
                        "size": 4
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            local data = {
                scheme = "http",
                type = "roundrobin",
                nodes = {
                    ["127.0.0.1:1980"] = 1,
                },
                pass_host = "rewrite",
                upstream_host = "b.com",
                keepalive_pool = {
                    size = 8
                }
            }
            local code, body = test('/apisix/admin/upstreams/2',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            for i = 1, 2 do
                local code, body = test('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "uri":"/hello/]] .. i .. [[",
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/hello"
                            }
                        },
                        "upstream_id": ]] .. i .. [[
                    }]])
                if code >= 300 then
                    ngx.status = code
                    ngx.print(body)
                    return
                end
            end
        }
    }
--- response_body



=== TEST 15: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
            for i = 0, 1 do
                local idx = i % 2 + 1
                local httpc = http.new()
                local res, err = httpc:request_uri(uri .. "/hello/" .. idx)
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.print(res.body)
            end
        }
    }
--- grep_error_log eval
qr/lua balancer: keepalive create pool, .*/
--- grep_error_log_out eval
qr/^lua balancer: keepalive create pool, crc32: \S+, size: 4
lua balancer: keepalive create pool, crc32: \S+, size: 8
$/



=== TEST 16: backend serve http and grpc with the same port
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local test = require("lib.test_admin").test
            local json = require("toolkit.json")

            local data = {
                uri = "",
                upstream = {
                    scheme = "",
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:10054"] = 1,
                    },
                    keepalive_pool = {
                        size = 4
                    }
                }
            }

            data.uri = "/helloworld.Greeter/SayHello"
            data.upstream.scheme = "grpc"
            local code, body = test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

            data.uri = "/hello"
            data.upstream.scheme = "http"
            local code, body = test('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                json.encode(data)
            )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end

        }
    }
--- response_body



=== TEST 17: hit http
--- request
GET /hello
--- response_body chomp
hello http



=== TEST 18: hit grpc
--- http2
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
--- response_body
{
  "message": "Hello apisix"
}
