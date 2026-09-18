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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    # TLS fronts in front of the plain redis on 6379, like a name-routed cloud
    # endpoint: 6395 only reaches redis when the SNI is "test.com", any other
    # SNI (or none) lands on the plain HTTP test server; 6396 reaches redis
    # regardless of SNI. test.com resolves to 127.0.0.1 via /etc/hosts.
    # Only the request blocks enable it: stream_enable replaces location /t.
    $block->set_value("extra_stream_config", <<_EOC_);
    server {
        listen 6395 ssl;
        server_name test.com;
        ssl_certificate ../../certs/apisix.crt;
        ssl_certificate_key ../../certs/apisix.key;
        proxy_pass 127.0.0.1:6379;
    }
    server {
        listen 6395 ssl default_server;
        server_name _;
        ssl_certificate ../../certs/apisix.crt;
        ssl_certificate_key ../../certs/apisix.key;
        proxy_pass 127.0.0.1:1980;
    }
    server {
        listen 6396 ssl;
        ssl_certificate ../../certs/apisix.crt;
        ssl_certificate_key ../../certs/apisix.key;
        proxy_pass 127.0.0.1:6379;
    }
_EOC_

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $extra_init_worker_by_lua = $block->extra_init_worker_by_lua // "";
    $extra_init_worker_by_lua .= <<_EOC_;
        require("lib.test_redis").flush_all()
_EOC_
    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);
});

run_tests;

__DATA__

=== TEST 1: limit-count: redis behind a TLS front that routes by SNI
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "test.com",
                            "redis_port": 6395,
                            "redis_ssl": true,
                            "redis_ssl_verify": false
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: the SNI reaches redis, the counter works
--- stream_enable
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]



=== TEST 3: limit-count: redis_ssl_verify also checks the certificate against redis_host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "test.com",
                            "redis_port": 6395,
                            "redis_ssl": true,
                            "redis_ssl_verify": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: verified connection, the counter works
--- stream_enable
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]



=== TEST 5: limit-count: an IP literal redis_host sends no SNI and skips the host check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6396,
                            "redis_ssl": true,
                            "redis_ssl_verify": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: the counter works although the certificate is for test.com
--- stream_enable
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]



=== TEST 7: limit-req (shared redis util): redis behind the SNI-routed front
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-req": {
                            "rate": 4,
                            "burst": 1,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "test.com",
                            "redis_port": 6395,
                            "redis_ssl": true,
                            "redis_ssl_verify": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: the SNI reaches redis, the limiter works
--- stream_enable
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- error_code eval
[200, 200]



=== TEST 9: limit-count: redis_server_name overrides the SNI when redis_host is an IP
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6395,
                            "redis_ssl": true,
                            "redis_ssl_verify": true,
                            "redis_server_name": "test.com"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: the SNI-routed front reaches redis and the certificate matches the SNI
--- stream_enable
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]



=== TEST 11: two routes with different redis_server_name must not share a keepalive pool
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for i, sni in ipairs({"test.com", "other.com"}) do
                local code, body = t('/apisix/admin/routes/' .. i,
                    ngx.HTTP_PUT,
                    [[{
                        "uri": "/hello]] .. (i == 1 and "" or "1") .. [[",
                        "plugins": {
                            "limit-count": {
                                "count": 100,
                                "time_window": 60,
                                "key": "remote_addr",
                                "policy": "redis",
                                "redis_host": "127.0.0.1",
                                "redis_port": 6395,
                                "redis_ssl": true,
                                "redis_server_name": "]] .. sni .. [["
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                    }]]
                    )
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 12: the route whose SNI lands on the HTTP server never borrows the other route's redis connection
--- stream_enable
--- pipelined_requests eval
["GET /hello", "GET /hello1", "GET /hello", "GET /hello1"]
--- error_code eval
[200, 500, 200, 500]
--- no_error_log
[alert]



=== TEST 13: limit-count: a DNS redis_host not covered by the certificate fails the host check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "admin.apisix.dev",
                            "redis_port": 6396,
                            "redis_ssl": true,
                            "redis_ssl_verify": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: the certificate is for test.com, so the verified connection is refused
--- stream_enable
--- request
GET /hello
--- error_code: 500
--- error_log
certificate host mismatch



=== TEST 15: limit-count: redis_server_name names the certificate host for that DNS alias
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "admin.apisix.dev",
                            "redis_port": 6396,
                            "redis_ssl": true,
                            "redis_ssl_verify": true,
                            "redis_server_name": "test.com"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: the override matches the certificate, the counter works
--- stream_enable
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]
