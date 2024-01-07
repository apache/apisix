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
    - brotli
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
                        "brotli": {
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
Accept-Encoding: br
Content-Type: text/html
--- response_headers
Content-Encoding: br
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
Content-Encoding: br
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
Vary:



=== TEST 5: hit, br in multi Accept-Encoding
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip, br
Content-Type: text/html
--- response_headers
Content-Encoding: br
Vary:



=== TEST 6: hit, no br in multi Accept-Encoding, but wildcard
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip, *
Content-Type: text/html
--- response_headers
Content-Encoding: br
Vary:



=== TEST 7: not hit, no br in multi Accept-Encoding
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip, deflate
Content-Type: text/html
--- response_headers
Vary:



=== TEST 8: hit, multi Accept-Encoding with quality
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip;q=0.5, br;q=0.6
Content-Type: text/html
--- response_headers
Content-Encoding: br
Vary:



=== TEST 9: not hit, multi Accept-Encoding with quality and disable br
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: gzip;q=0.5, br;q=0
Content-Type: text/html
--- response_headers
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
Content-Encoding: br
Vary:



=== TEST 11: default buffers and compress level
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.brotli")
            local core = require("apisix.core")
            local json = require("toolkit.json")

            for _, conf in ipairs({
                {},
                {mode = 1},
                {comp_level = 5},
                {comp_level = 5, lgwin = 12},
                {comp_level = 5, lgwin = 12, vary = true},
                {comp_level = 5, lgwin = 12, lgblock = 16, vary = true},
                {mode = 2, comp_level = 5, lgwin = 12, lgblock = 16, vary = true},
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
{"comp_level":6,"http_version":1.1,"lgblock":0,"lgwin":19,"min_length":20,"mode":0,"types":["text/html"]}
{"comp_level":6,"http_version":1.1,"lgblock":0,"lgwin":19,"min_length":20,"mode":1,"types":["text/html"]}
{"comp_level":5,"http_version":1.1,"lgblock":0,"lgwin":19,"min_length":20,"mode":0,"types":["text/html"]}
{"comp_level":5,"http_version":1.1,"lgblock":0,"lgwin":12,"min_length":20,"mode":0,"types":["text/html"]}
{"comp_level":5,"http_version":1.1,"lgblock":0,"lgwin":12,"min_length":20,"mode":0,"types":["text/html"],"vary":true}
{"comp_level":5,"http_version":1.1,"lgblock":16,"lgwin":12,"min_length":20,"mode":0,"types":["text/html"],"vary":true}
{"comp_level":5,"http_version":1.1,"lgblock":16,"lgwin":12,"min_length":20,"mode":2,"types":["text/html"],"vary":true}



=== TEST 12: compress level
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
                        "brotli": {
                            "comp_level": 0
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
                    "brotli": {
                        "comp_level": 11
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



=== TEST 13: hit
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



=== TEST 14: min length
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
                        "brotli": {
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



=== TEST 15: not hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: br
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 16: http version
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
                        "brotli": {
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



=== TEST 17: not hit
--- request
POST /echo HTTP/1.0
0123456789
012345678
--- more_headers
Accept-Encoding: br
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 18: hit again
--- request
POST /echo HTTP/1.1
0123456789
012345678
--- more_headers
Accept-Encoding: br
Content-Type: text/html
--- response_headers
Content-Encoding: br



=== TEST 19: types
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
                        "brotli": {
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



=== TEST 20: not hit
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: br
Content-Type: text/html
--- response_headers
Content-Encoding:



=== TEST 21: hit again
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: br
Content-Type: text/xml
--- response_headers
Content-Encoding: br



=== TEST 22: hit with charset
--- request
POST /echo
0123456789
012345678
--- more_headers
Accept-Encoding: br
Content-Type: text/plain; charset=UTF-8
--- response_headers
Content-Encoding: br



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
                        "brotli": {
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
Accept-Encoding: br
Content-Type: video/3gpp
--- response_headers
Content-Encoding: br



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
                        "brotli": {
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
Accept-Encoding: br
Vary: upstream
Content-Type: text/html
--- response_headers
Content-Encoding: br
Vary: upstream, Accept-Encoding



=== TEST 27: schema check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, case in ipairs({
                {input = {
                    types = {}
                }},
                {input = {
                    min_length = 0
                }},
                {input = {
                    mode = 4
                }},
                {input = {
                    comp_level = 12
                }},
                {input = {
                    http_version = 2
                }},
                {input = {
                    lgwin = 100
                }},
                {input = {
                    lgblock = 8
                }},
                {input = {
                    vary = 0
                }}
            }) do
                local code, body = t('/apisix/admin/global_rules/1',
                    ngx.HTTP_PUT,
                    {
                        id = "1",
                        plugins = {
                            ["brotli"] = case.input
                        }
                    }
                )
                ngx.print(body)
            end
    }
}
--- response_body
{"error_msg":"failed to check the configuration of plugin brotli err: property \"types\" validation failed: object matches none of the required"}
{"error_msg":"failed to check the configuration of plugin brotli err: property \"min_length\" validation failed: expected 0 to be at least 1"}
{"error_msg":"failed to check the configuration of plugin brotli err: property \"mode\" validation failed: expected 4 to be at most 2"}
{"error_msg":"failed to check the configuration of plugin brotli err: property \"comp_level\" validation failed: expected 12 to be at most 11"}
{"error_msg":"failed to check the configuration of plugin brotli err: property \"http_version\" validation failed: matches none of the enum values"}
{"error_msg":"failed to check the configuration of plugin brotli err: property \"lgwin\" validation failed: matches none of the enum values"}
{"error_msg":"failed to check the configuration of plugin brotli err: property \"lgblock\" validation failed: matches none of the enum values"}
{"error_msg":"failed to check the configuration of plugin brotli err: property \"vary\" validation failed: wrong type: expected boolean, got number"}



=== TEST 28: body checksum
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
                        "brotli": {
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



=== TEST 29: hit - decompressed respone body same as requset body
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/echo"
            local httpc = http.new()
            local req_body = ("abcdf01234"):rep(1024)
            local res, err = httpc:request_uri(uri,
                {method = "POST", headers = {["Accept-Encoding"] = "br"}, body = req_body})
            if not res then
                ngx.say(err)
                return
            end

            local brotli = require "brotli"
            local decompressor = brotli.decompressor:new()
            local chunk = decompressor:decompress(res.body)
            local chunk_fin = decompressor:finish()
            local chunks = chunk .. chunk_fin
            if #chunks == #req_body then
                ngx.say("ok")
            end
        }
    }
--- response_body
ok



=== TEST 30: mock upstream compressed response
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/mock_compressed_upstream_response",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "brotli": {
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



=== TEST 31: hit - skip brotli compression of compressed upsteam response
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/mock_compressed_upstream_response"
            local httpc = http.new()
            local req_body = ("abcdf01234"):rep(1024)
            local res, err = httpc:request_uri(uri,
                {method = "POST", headers = {["Accept-Encoding"] = "gzip, br"}, body = req_body})
            if not res then
                ngx.say(err)
                return
            end
            if res.headers["Content-Encoding"] == 'gzip' then
                ngx.say("ok")
            end
        }
    }
--- request
GET /t
--- more_headers
Accept-Encoding: gzip, br
Vary: upstream
Content-Type: text/html
--- response_body
ok
