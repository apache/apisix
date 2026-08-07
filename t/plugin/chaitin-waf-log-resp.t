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

add_block_preprocessor(sub {
    my ($block) = @_;

    # pass_keepalive() keeps the connection usable for the response report,
    # which the client sends over the same pooled connection
    my $handler = $block->waf_server_handler // "pass_keepalive";
    my $stream_default_server = <<_EOC_;
    server {
        listen 8088;
        content_by_lua_block {
            require("lib.chaitin_waf_server").$handler()
        }
    }
_EOC_

    $block->set_value("extra_stream_config", $stream_default_server);
    $block->set_value("stream_conf_enable", 1);

    # setup default conf.yaml
    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
apisix:
  stream_proxy:                 # TCP/UDP L4 proxy
   only: true                  # Enable L4 proxy only without L7 proxy.
   tcp:
     - addr: 9100              # Set the TCP proxy listening ports.
       tls: true
     - addr: "127.0.0.1:9101"
   udp:                        # Set the UDP proxy listening ports.
     - 9200
     - "127.0.0.1:9201"
plugins:
    - chaitin-waf
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->request) {
        # use /do instead of /t because stream server will inject a default /t location
        $block->set_value("request", "GET /do");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: configure the WAF service
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/chaitin-waf',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": [
                        {
                            "host": "127.0.0.1",
                            "port": 8088
                        }
                    ]
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: the response is reported to the WAF service
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "plugins": {
                        "chaitin-waf": {
                            "config": {
                                "log_resp": true
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
            if not res then
                return ngx.say("request failed: ", err)
            end
            ngx.say("upstream response: ", res.body)
            ngx.say("waf header: ", res.headers["X-APISIX-CHAITIN-WAF"])

            -- give the timer that reports the response a chance to run
            ngx.sleep(0.3)
        }
    }
--- response_body
upstream response: hello world
waf header: yes
--- error_log
lua-resty-t1k: reported response
--- log_level: debug



=== TEST 3: buffer the whole response body when it fits
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["POST"],
                    "plugins": {
                        "chaitin-waf": {
                            "config": {
                                "log_resp": true
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            -- /echo answers with the request body, so this yields a 100 byte
            -- response, well under the 4 KB default
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = string.rep("a", 100),
            })
            if not res then
                return ngx.say("request failed: ", err)
            end
            ngx.say("client body size: ", #res.body)

            ngx.sleep(0.3)
        }
    }
--- response_body
client body size: 100
--- error_log
lua-resty-t1k: response body received completely, total size: 100 bytes, truncated size: 100 bytes
--- log_level: debug



=== TEST 4: truncate the buffered response body to resp_body_size
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["POST"],
                    "plugins": {
                        "chaitin-waf": {
                            "config": {
                                "log_resp": true,
                                "resp_body_size": 1
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = string.rep("a", 4096),
            })
            if not res then
                return ngx.say("request failed: ", err)
            end
            -- the client still receives the whole response
            ngx.say("client body size: ", #res.body)

            ngx.sleep(0.3)
        }
    }
--- response_body
client body size: 4096
--- error_log
lua-resty-t1k: response body received completely, total size: 4096 bytes, truncated size: 1024 bytes
--- log_level: debug



=== TEST 5: buffer no response body when resp_body_size is zero
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "plugins": {
                        "chaitin-waf": {
                            "config": {
                                "log_resp": true,
                                "resp_body_size": 0
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
            if not res then
                return ngx.say("request failed: ", err)
            end
            ngx.say("upstream response: ", res.body)

            ngx.sleep(0.3)
        }
    }
--- response_body
upstream response: hello world
--- error_log
lua-resty-t1k: skip response body buffering for non-positive limit: 0
--- log_level: debug



=== TEST 6: skip an extra ignored content type
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["POST"],
                    "plugins": {
                        "chaitin-waf": {
                            "config": {
                                "log_resp": true,
                                "extra_ignored_content_types": "text/csv"
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            -- /echo reflects a resp-* request header as a response header, so
            -- this makes the upstream answer with an ignored content type
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/echo", {
                method = "POST",
                body = "a,b,c",
                headers = { ["resp-content-type"] = "text/csv" },
            })
            if not res then
                return ngx.say("request failed: ", err)
            end
            ngx.say("content type: ", res.headers["Content-Type"])

            ngx.sleep(0.3)
        }
    }
--- response_body
content type: text/csv
--- error_log
lua-resty-t1k: skip response logging
--- log_level: debug



=== TEST 7: do not report the response when log_resp is off
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "plugins": {
                        "chaitin-waf": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
            if not res then
                return ngx.say("request failed: ", err)
            end
            ngx.say("waf header: ", res.headers["X-APISIX-CHAITIN-WAF"])

            ngx.sleep(0.3)
        }
    }
--- response_body
waf header: yes
--- error_log
lua-resty-t1k: skip response logging
--- log_level: debug



=== TEST 8: a failure to report the response is logged
--- waf_server_handler: pass
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "plugins": {
                        "chaitin-waf": {
                            "config": {
                                "log_resp": true
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                 }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            -- pass() answers the request report and then goes away, so the
            -- response report finds the pooled connection unusable and fails.
            -- Before the failure was logged, this was silent.
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:1984/hello")
            if not res then
                return ngx.say("request failed: ", err)
            end
            -- the response still reaches the client unharmed
            ngx.say("upstream response: ", res.body)
            ngx.say("waf header: ", res.headers["X-APISIX-CHAITIN-WAF"])

            ngx.sleep(0.3)
        }
    }
--- response_body
upstream response: hello world
waf header: yes
--- error_log
lua-resty-t1k: failed to report response
--- log_level: error
