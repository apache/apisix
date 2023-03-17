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
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->response_body) {
        $block->set_value("response_body", "passed\n");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});


our $debug_config = t::APISIX::read_file("conf/debug.yaml");
$debug_config =~ s/basic:\n  enable: false/basic:\n  enable: true/;
$debug_config =~ s/hook_conf:\n  enable: false/hook_conf:\n  enable: true/;

run_tests;

__DATA__

=== TEST 1: configure non-auth plugins in the consumer and run it's rewrite phase
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                 ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        },
                        "proxy-rewrite": {
                            "uri": "/uri/plugin_proxy_rewrite",
                            "headers": {
                                "X-Api-Engine": "APISIX",
                                "X-CONSUMER-ID": "1"
                            }
                        }
                    }
                }]]
                )

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "key-auth": {}
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
--- response_body
passed



=== TEST 2: hit routes
--- request
GET /hello
--- more_headers
apikey: auth-jack
--- response_body
uri: /uri/plugin_proxy_rewrite
apikey: auth-jack
host: localhost
x-api-engine: APISIX
x-consumer-id: 1
x-real-ip: 127.0.0.1



=== TEST 3: trace plugins info for debug
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local ngx_re = require("ngx.re")
            local http = require "resty.http"
            local httpc = http.new()
            local headers = {}
            headers["apikey"] = "auth-jack"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = headers,
                })
            local debug_header = res.headers["Apisix-Plugins"]
            local arr = ngx_re.split(debug_header, ", ")
            local hash = {}
            for i, v in ipairs(arr) do
                hash[v] = true
            end
            ngx.status = res.status
            ngx.say(json.encode(hash))
        }
    }
--- response_body
{"key-auth":true,"proxy-rewrite":true}



=== TEST 4: configure non-auth plugins in the route and run it's rewrite phase
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                 ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        }
                    }
                }]]
                )

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "key-auth": {},
                            "proxy-rewrite": {
                                "uri": "/uri/plugin_proxy_rewrite",
                                "headers": {
                                    "X-Api-Engine": "APISIX",
                                    "X-CONSUMER-ID": "1"
                                }
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
--- response_body
passed



=== TEST 5: hit routes
--- request
GET /hello
--- more_headers
apikey: auth-jack
--- response_body
uri: /uri/plugin_proxy_rewrite
apikey: auth-jack
host: localhost
x-api-engine: APISIX
x-consumer-id: 1
x-real-ip: 127.0.0.1



=== TEST 6: trace plugins info for debug
--- debug_config eval: $::debug_config
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local ngx_re = require("ngx.re")
            local http = require "resty.http"
            local httpc = http.new()
            local headers = {}
            headers["apikey"] = "auth-jack"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {
                    method = "GET",
                    headers = headers,
                })
            local debug_header = res.headers["Apisix-Plugins"]
            local arr = ngx_re.split(debug_header, ", ")
            local hash = {}
            for i, v in ipairs(arr) do
                hash[v] = true
            end
            ngx.status = res.status
            ngx.say(json.encode(hash))
        }
    }
--- response_body
{"key-auth":true,"proxy-rewrite":true}



=== TEST 7: configure non-auth plugins in the consumer and run it's rewrite phase
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack',
                 ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        },
                        "ip-restriction": {
                            "blacklist": [
                                "127.0.0.0/24"
                            ]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "key-auth": {}
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
--- response_body
passed



=== TEST 8: hit routes and ip-restriction work well
--- request
GET /hello
--- more_headers
apikey: auth-jack
--- error_code: 403
--- response_body
{"message":"Your IP address is not allowed"}



=== TEST 9: use the latest consumer modifiedIndex as lrucache key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ip-restriction": {
                            "whitelist": ["1.1.1.1"]
                        },
                        "basic-auth": {}
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugin_config_id": "1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uris": ["/hello"]
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local headers = {
                ["Authorization"] = "Basic Zm9vOmJhcg=="
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            ngx.print(res.body)

            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "ip-restriction": {
                            "whitelist": ["1.1.1.1", "127.0.0.1"]
                        },
                        "basic-auth": {}
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local res, err = httpc:request_uri(uri, {headers = headers})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bala"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local headers = {
                ["Authorization"] = "Basic Zm9vOmJhbGE="
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- response_body
{"message":"Your IP address is not allowed"}
hello world
hello world



=== TEST 10: consumer should work if the etcd connection failed during starting
--- extra_init_by_lua
local etcd_apisix  = require("apisix.core.etcd")
etcd_apisix.get_etcd_syncer = function ()
    return nil, "", "ouch"
end
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local headers = {
                ["Authorization"] = "Basic Zm9vOmJhbGE="
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- response_body
hello world
--- error_log
failed to fetch data from etcd
