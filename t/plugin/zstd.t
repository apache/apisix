#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    my $extra_yaml_config = <<_EOC_;
plugins:
    - zstd
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);
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
                        "zstd": {
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



=== TEST 2: hit, single Accept-Encoding
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: zstd
Content-Type: text/html
--- response_headers
Content-Encoding: zstd
Vary:



=== TEST 3: hit, single wildcard Accept-Encoding
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: *
Content-Type: text/html
--- response_headers
Content-Encoding: zstd
Vary:



=== TEST 4: not hit, single Accept-Encoding
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip
Content-Type: text/html
--- response_headers
Content-Encoding:
Vary:



=== TEST 5: hit, zstd in multi Accept-Encoding
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip, zstd
Content-Type: text/html
--- response_headers
Content-Encoding: zstd
Vary:



=== TEST 6: hit, no zstd in multi Accept-Encoding, but wildcard
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip, *
Content-Type: text/html
--- response_headers
Content-Encoding: zstd
Vary:



=== TEST 7: not hit, no zstd in multi Accept-Encoding
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip, deflate
Content-Type: text/html
--- response_headers
Content-Encoding:
Vary:



=== TEST 8: hit, multi Accept-Encoding with quality
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip;q=0.5, zstd;q=0.6
Content-Type: text/html
--- response_headers
Content-Encoding: zstd
Vary:



=== TEST 9: not hit, multi Accept-Encoding with quality and disable zstd
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip;q=0.5, zstd;q=0
Content-Type: text/html
--- response_headers
Content-Encoding:
Vary:



=== TEST 10: hit, multi Accept-Encoding with quality and wildcard
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip;q=0.8, deflate, sdch;q=0.6, *;q=0.1
Content-Type: text/html
--- response_headers
Content-Encoding: zstd
Vary:



=== TEST 11: default compression level and attributes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zstd")
            local core = require("apisix.core")
            local json = require("toolkit.json")

            for _, conf in ipairs({
                {},
                {comp_level = 5},
                {comp_level = 19},
                {comp_level = 5, vary = true},
            }) do
                local ok, err = plugin.check_schema(conf)
                if not ok then
                    ngx.say(err)
                    return
                end
                ngx.say(json.encode(conf))
            end
        }
    }
--- response_body
{"comp_level":3,"http_version":1.1,"min_length":20,"types":["text/html"]}
{"comp_level":5,"http_version":1.1,"min_length":20,"types":["text/html"]}
{"comp_level":19,"http_version":1.1,"min_length":20,"types":["text/html"]}
{"comp_level":5,"http_version":1.1,"min_length":20,"types":["text/html"],"vary":true}



=== TEST 12: invalid attributes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zstd")

            for _, conf in ipairs({
                {types = {}},
                {min_length = 0},
                {comp_level = 0},
                {comp_level = 20},
                {http_version = 2},
                {types = {"", "text/html"}},
            }) do
                local ok = plugin.check_schema(conf)
                ngx.say(ok)
            end
        }
    }
--- response_body
false
false
false
false
false
false



=== TEST 13: compression level
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
                        "zstd": {
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
                    "zstd": {
                        "comp_level": 19
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



=== TEST 14: hit, higher level compresses better
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/echo"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri,
                {method = "POST", headers = {x = "1", ["Accept-Encoding"] = "zstd",
                 ["Content-Type"] = "text/html"}, body = ("0123"):rep(1024)})
            if not res then
                ngx.say(err)
                return
            end
            local low_level = res.body
            local res, err = httpc:request_uri(uri,
                {method = "POST", headers = {x = "2", ["Accept-Encoding"] = "zstd",
                 ["Content-Type"] = "text/html"}, body = ("0123"):rep(1024)})
            if not res then
                ngx.say(err)
                return
            end
            if #low_level < 4096 and #res.body < #low_level then
                ngx.say("ok")
            end
        }
    }
--- response_body
ok



=== TEST 15: min length
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
                        "zstd": {
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



=== TEST 16: not hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: zstd
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 17: http version
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
                        "zstd": {
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



=== TEST 18: not hit
--- request
POST /echo HTTP/1.0
0123456789
012345678
--- more_headers
Accept-Encoding: zstd
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 19: hit again
--- request
POST /echo HTTP/1.1
0123456789
012345678
--- more_headers
Accept-Encoding: zstd
Content-Type: text/html
--- response_headers
Content-Encoding: zstd



=== TEST 20: types
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
                        "zstd": {
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



=== TEST 21: not hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: zstd
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 22: hit, type in list
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: zstd
Content-Type: text/xml
--- response_headers
Content-Encoding: zstd



=== TEST 23: match all types
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
                        "zstd": {
                            "types": "*"
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



=== TEST 24: hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: zstd
Content-Type: video/3gpp
--- response_headers
Content-Encoding: zstd



=== TEST 25: vary
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
                        "zstd": {
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



=== TEST 26: hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: zstd
Vary: upstream
Content-Type: text/html
--- response_headers
Content-Encoding: zstd
Vary: upstream, Accept-Encoding



=== TEST 27: hit - decompressed response body same as request body
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/echo"
            local httpc = http.new()
            local req_body = ("abcdf01234"):rep(1024)
            local res, err = httpc:request_uri(uri,
                {method = "POST", headers = {["Accept-Encoding"] = "zstd",
                 ["Content-Type"] = "text/html"}, body = req_body})
            if not res then
                ngx.say(err)
                return
            end

            local zstd = require "apisix.plugins.zstd.binding"
            local decompressor = zstd.decompressor:new()
            local chunk, derr = decompressor:decompress(res.body)
            if not chunk then
                ngx.say("decompress err: ", derr)
                return
            end
            local chunk_fin = decompressor:finish()
            local chunks = chunk .. chunk_fin
            if #chunks == #req_body then
                ngx.say("ok")
            end
        }
    }
--- response_body
ok
