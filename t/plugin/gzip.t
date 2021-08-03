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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "gzip": {
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



=== TEST 2: hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Content-Type: text/html
--- response_headers
Content-Encoding: gzip
Vary:



=== TEST 3: default buffers and compress level
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.gzip")
            local core = require("apisix.core")
            local json = require("toolkit.json")

            for _, conf in ipairs({
                {},
                {buffers = {}},
                {buffers = {number = 1}},
                {buffers = {size = 1}},
            }) do
                local ok, err = plugin.check_schema(conf)
                if not ok then
                    ngx.say(err)
                    return
                end
                ngx.say(json.encode(conf.buffers))
            end
        }
    }
--- response_body
{"number":32,"size":4096}
{"number":32,"size":4096}
{"number":1,"size":4096}
{"number":32,"size":1}



=== TEST 4: compress level
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/echo",
                    "vars": [["http_x", "==", "1"]],
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "gzip": {
                            "comp_level": 1
                        }
                    }
                }]=]
            )

        if code >= 300 then
            ngx.status = code
            return
        end

        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [=[{
                "uri": "/echo",
                "vars": [["http_x", "==", "2"]],
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1980": 1
                    }
                },
                "plugins": {
                    "gzip": {
                        "comp_level": 9
                    }
                }
            }]=]
        )

        if code >= 300 then
            ngx.status = code
            return
        end
        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 5: hit
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/echo"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri,
                {method = "POST", headers = {x = "1"}, body = ("0123"):rep(1024)})
            if not res then
                ngx.say(err)
                return
            end
            local less_compressed = res.body
            local res, err = httpc:request_uri(uri,
                {method = "POST", headers = {x = "2"}, body = ("0123"):rep(1024)})
            if not res then
                ngx.say(err)
                return
            end
            if #less_compressed < 4096 and #less_compressed < #res.body then
                ngx.say("ok")
            end
        }
    }
--- response_body
ok



=== TEST 6: min length
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "gzip": {
                            "min_length": 21
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



=== TEST 7: not hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 8: http version
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "gzip": {
                            "http_version": 1.1
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



=== TEST 9: not hit
--- request
POST /echo HTTP/1.0
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 10: hit again
--- request
POST /echo HTTP/1.1
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Content-Type: text/html
--- response_headers
Content-Encoding: gzip



=== TEST 11: types
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "gzip": {
                            "types": ["text/plain", "text/xml"]
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



=== TEST 12: not hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 13: hit again
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Content-Type: text/xml
--- response_headers
Content-Encoding: gzip



=== TEST 14: hit with charset
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Content-Type: text/plain; charset=UTF-8
--- response_headers
Content-Encoding: gzip



=== TEST 15: vary
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "gzip": {
                            "vary": true
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



=== TEST 16: hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Vary: upstream
Content-Type: text/html
--- response_headers
Content-Encoding: gzip
Vary: upstream, Accept-Encoding
