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
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: schema check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, case in ipairs({
                {input = {}},
                {input = {
                    source = "http_xff",
                    trusted_addresses = {"127.0.0.1/33"}
                }},
                {input = {
                    source = "http_xff",
                    trusted_addresses = {"::1/129"}
                }},
            }) do
                local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    {
                        uri = "/hello",
                        upstream = {
                            type = "roundrobin",
                            nodes = {
                                ["127.0.0.1:1980"] = 1
                            }
                        },
                        plugins = {
                            ["real-ip"] = case.input
                        }
                    }
                )
                ngx.print(body)
            end
    }
}
--- response_body
{"error_msg":"failed to check the configuration of plugin real-ip err: property \"source\" is required"}
{"error_msg":"failed to check the configuration of plugin real-ip err: property \"trusted_addresses\" validation failed: failed to validate item 1: object matches none of the required"}
{"error_msg":"failed to check the configuration of plugin real-ip err: invalid ip address: ::1/129"}



=== TEST 2: sanity
--- config
    location /t {
        content_by_lua_block {
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
                    },
                    "plugins": {
                        "real-ip": {
                            "source": "http_xff"
                        },
                        "ip-restriction": {
                            "whitelist": ["1.1.1.1"]
                        }
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



=== TEST 3: hit
--- request
GET /hello
--- more_headers
XFF: 1.1.1.1



=== TEST 4: with port
--- request
GET /hello
--- more_headers
XFF: 1.1.1.1:80



=== TEST 5: miss address
--- request
GET /hello
--- error_code: 403



=== TEST 6: bad address
--- request
GET /hello
--- more_headers
XFF: 1.1.1.1.1
--- error_code: 403



=== TEST 7: bad port
--- request
GET /hello
--- more_headers
XFF: 1.1.1.1:65536
--- error_code: 403



=== TEST 8: ipv6
--- config
    location /t {
        content_by_lua_block {
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
                    },
                    "plugins": {
                        "real-ip": {
                            "source": "http_xff"
                        },
                        "ip-restriction": {
                            "whitelist": ["::2"]
                        }
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



=== TEST 9: hit
--- request
GET /hello
--- more_headers
XFF: ::2



=== TEST 10: with port
--- request
GET /hello
--- more_headers
XFF: [::2]:80



=== TEST 11: with bracket
--- request
GET /hello
--- more_headers
XFF: [::2]



=== TEST 12: check port
--- config
    location /t {
        content_by_lua_block {
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
                    },
                    "plugins": {
                        "real-ip": {
                            "source": "http_xff"
                        },
                        "response-rewrite": {
                            "headers": {
                                "remote_port": "$remote_port"
                            }
                        }
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



=== TEST 13: hit
--- request
GET /hello
--- more_headers
XFF: 1.1.1.1:7090
--- response_headers
remote_port: 7090



=== TEST 14: X-Forwarded-For
--- config
    location /t {
        content_by_lua_block {
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
                    },
                    "plugins": {
                        "real-ip": {
                            "source": "http_x_forwarded_for"
                        },
                        "ip-restriction": {
                            "whitelist": ["::2"]
                        }
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



=== TEST 15: hit
--- request
GET /hello
--- more_headers
X-Forwarded-For: ::1, ::2



=== TEST 16: hit (multiple X-Forwarded-For)
--- request
GET /hello
--- more_headers
X-Forwarded-For: ::1
X-Forwarded-For: ::2



=== TEST 17: miss address
--- request
GET /hello
--- error_code: 403



=== TEST 18: trusted addresses (not trusted)
--- config
    location /t {
        content_by_lua_block {
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
                    },
                    "plugins": {
                        "real-ip": {
                            "trusted_addresses": ["192.128.0.0/16"],
                            "source": "http_x_forwarded_for"
                        },
                        "ip-restriction": {
                            "whitelist": ["1.1.1.1"]
                        }
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



=== TEST 19: hit
--- request
GET /hello
--- more_headers
X-Forwarded-For: 1.1.1.1
--- error_code: 403



=== TEST 20: trusted addresses (trusted)
--- config
    location /t {
        content_by_lua_block {
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
                    },
                    "plugins": {
                        "real-ip": {
                            "trusted_addresses": ["192.128.0.0/16", "127.0.0.0/24"],
                            "source": "http_x_forwarded_for"
                        },
                        "ip-restriction": {
                            "whitelist": ["1.1.1.1"]
                        }
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



=== TEST 21: hit
--- request
GET /hello
--- more_headers
X-Forwarded-For: 1.1.1.1



=== TEST 22: X-Forwarded-For and recursive
--- config
    location /t {
        content_by_lua_block {
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
                    },
                    "plugins": {
                        "real-ip": {
                            "trusted_addresses": ["192.128.0.0/16", "127.0.0.0/24"],
                            "source": "http_x_forwarded_for",
                            "recursive": true
                        },
                        "ip-restriction": {
                            "whitelist": ["1.1.1.1"]
                        }
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



=== TEST 23: hit
--- request
GET /hello
--- more_headers
X-Forwarded-For: 1.1.1.1, 192.128.1.1, 127.0.0.1
