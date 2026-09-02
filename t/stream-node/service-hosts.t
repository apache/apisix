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

log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    # The TLS requests are sent from inside the same nginx instance that runs
    # the setup, so that the SNI router is exercised only once the stream
    # subsystem has synced the configuration from etcd.
    # An empty response body therefore means that no stream route was matched:
    # apisix closes the connection without proxying anything.
    $block->set_value("stream_conf_enable", 1);

    my $config = $block->config // '';
    $config .= <<_EOC_;
    location /tls {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(2000)
            local ok, err = sock:connect("127.0.0.1", 2005)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local sess, err = sock:sslhandshake(nil, ngx.var.arg_sni, false)
            if not sess then
                sock:close()
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            local bytes, err = sock:send("mmm")
            if not bytes then
                sock:close()
                ngx.say("send stream request error: ", err)
                return
            end

            -- reaching peer closure yields `nil, "closed", partial`; the bytes
            -- read so far are the response
            local data, err, partial = sock:receive("*a")
            sock:close()
            if not data and err ~= "closed" then
                ngx.say("receive stream response error: ", err)
                return
            end

            ngx.print(data or partial or "")
        }
    }
_EOC_

    $block->set_value("config", $config);
});

run_tests();

__DATA__

=== TEST 1: a stream route without sni is matched by every host of its service
--- config
    location /setup {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local code = t.test('/apisix/admin/ssls/1', ngx.HTTP_PUT,
                core.json.encode({cert = ssl_cert, key = ssl_key, sni = "*"}))
            if code >= 300 then
                ngx.say("failed to create ssl: ", code)
                return
            end

            code = t.test('/apisix/admin/services/1', ngx.HTTP_PUT,
                [[{
                    "hosts": ["a.test.com", "b.test.com"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1995": 1},
                        "type": "roundrobin"
                    }
                }]])
            if code >= 300 then
                ngx.say("failed to create service: ", code)
                return
            end

            code = t.test('/apisix/admin/stream_routes/1', ngx.HTTP_PUT,
                [[{"service_id": 1}]])
            if code >= 300 then
                ngx.say("failed to create stream route: ", code)
                return
            end

            ngx.sleep(0.5)
            ngx.say("passed")
        }
    }
--- pipelined_requests eval
["GET /setup", "GET /tls?sni=a.test.com", "GET /tls?sni=b.test.com", "GET /tls?sni=c.test.com"]
--- response_body eval
["passed\n", "hello world\n", "hello world\n", ""]



=== TEST 2: the sni of the stream route wins over the hosts of its service
--- config
    location /setup {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local code = t.test('/apisix/admin/ssls/1', ngx.HTTP_PUT,
                core.json.encode({cert = ssl_cert, key = ssl_key, sni = "*"}))
            if code >= 300 then
                ngx.say("failed to create ssl: ", code)
                return
            end

            code = t.test('/apisix/admin/services/1', ngx.HTTP_PUT,
                [[{
                    "hosts": ["a.test.com"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1995": 1},
                        "type": "roundrobin"
                    }
                }]])
            if code >= 300 then
                ngx.say("failed to create service: ", code)
                return
            end

            code = t.test('/apisix/admin/stream_routes/1', ngx.HTTP_PUT,
                [[{"sni": "x.test.com", "service_id": 1}]])
            if code >= 300 then
                ngx.say("failed to create stream route: ", code)
                return
            end

            ngx.sleep(0.5)
            ngx.say("passed")
        }
    }
--- pipelined_requests eval
["GET /setup", "GET /tls?sni=x.test.com", "GET /tls?sni=a.test.com"]
--- response_body eval
["passed\n", "hello world\n", ""]



=== TEST 3: a wildcard host of the service is matched like a wildcard sni
--- config
    location /setup {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local code = t.test('/apisix/admin/ssls/1', ngx.HTTP_PUT,
                core.json.encode({cert = ssl_cert, key = ssl_key, sni = "*"}))
            if code >= 300 then
                ngx.say("failed to create ssl: ", code)
                return
            end

            code = t.test('/apisix/admin/services/1', ngx.HTTP_PUT,
                [[{
                    "hosts": ["*.test.com"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1995": 1},
                        "type": "roundrobin"
                    }
                }]])
            if code >= 300 then
                ngx.say("failed to create service: ", code)
                return
            end

            code = t.test('/apisix/admin/stream_routes/1', ngx.HTTP_PUT,
                [[{"service_id": 1}]])
            if code >= 300 then
                ngx.say("failed to create stream route: ", code)
                return
            end

            ngx.sleep(0.5)
            ngx.say("passed")
        }
    }
--- pipelined_requests eval
["GET /setup", "GET /tls?sni=a.test.com", "GET /tls?sni=a.b.test.com", "GET /tls?sni=test.org"]
--- response_body eval
["passed\n", "hello world\n", "hello world\n", ""]



=== TEST 4: a bare `*` host puts no restriction on the sni
--- config
    location /setup {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local code = t.test('/apisix/admin/ssls/1', ngx.HTTP_PUT,
                core.json.encode({cert = ssl_cert, key = ssl_key, sni = "*"}))
            if code >= 300 then
                ngx.say("failed to create ssl: ", code)
                return
            end

            code = t.test('/apisix/admin/services/1', ngx.HTTP_PUT,
                [[{
                    "hosts": ["*"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1995": 1},
                        "type": "roundrobin"
                    }
                }]])
            if code >= 300 then
                ngx.say("failed to create service: ", code)
                return
            end

            code = t.test('/apisix/admin/stream_routes/1', ngx.HTTP_PUT,
                [[{"remote_addr": "127.0.0.1", "service_id": 1}]])
            if code >= 300 then
                ngx.say("failed to create stream route: ", code)
                return
            end

            ngx.sleep(0.5)
            ngx.say("passed")
        }
    }
--- pipelined_requests eval
["GET /setup", "GET /tls?sni=whatever.test.com", "GET /tls?sni=another.test.org"]
--- response_body eval
["passed\n", "hello world\n", "hello world\n"]



=== TEST 5: the hosts of the service are matched case-insensitively
--- config
    location /setup {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local code = t.test('/apisix/admin/ssls/1', ngx.HTTP_PUT,
                core.json.encode({cert = ssl_cert, key = ssl_key, sni = "*"}))
            if code >= 300 then
                ngx.say("failed to create ssl: ", code)
                return
            end

            code = t.test('/apisix/admin/services/1', ngx.HTTP_PUT,
                [[{
                    "hosts": ["Mixed.TEST.com"],
                    "upstream": {
                        "nodes": {"127.0.0.1:1995": 1},
                        "type": "roundrobin"
                    }
                }]])
            if code >= 300 then
                ngx.say("failed to create service: ", code)
                return
            end

            code = t.test('/apisix/admin/stream_routes/1', ngx.HTTP_PUT,
                [[{"service_id": 1}]])
            if code >= 300 then
                ngx.say("failed to create stream route: ", code)
                return
            end

            ngx.sleep(0.5)
            ngx.say("passed")
        }
    }
--- pipelined_requests eval
["GET /setup", "GET /tls?sni=mixed.test.com", "GET /tls?sni=other.test.com"]
--- response_body eval
["passed\n", "hello world\n", ""]


=== TEST 6: the sni of the stream route is matched case-insensitively
--- config
    location /setup {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local code = t.test('/apisix/admin/ssls/1', ngx.HTTP_PUT,
                core.json.encode({cert = ssl_cert, key = ssl_key, sni = "*"}))
            if code >= 300 then
                ngx.say("failed to create ssl: ", code)
                return
            end

            code = t.test('/apisix/admin/stream_routes/1', ngx.HTTP_PUT,
                [[{
                    "sni": "Mixed.SNI.com",
                    "upstream": {
                        "nodes": {"127.0.0.1:1995": 1},
                        "type": "roundrobin"
                    }
                }]])
            if code >= 300 then
                ngx.say("failed to create stream route: ", code)
                return
            end

            ngx.sleep(0.5)
            ngx.say("passed")
        }
    }
--- pipelined_requests eval
["GET /setup", "GET /tls?sni=mixed.sni.com", "GET /tls?sni=other.sni.com"]
--- response_body eval
["passed\n", "hello world\n", ""]
