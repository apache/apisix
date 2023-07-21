use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $stream_default_server = <<_EOC_;
    server {
        listen 8088;
        listen 8089;
        content_by_lua_block {
            require("lib.chaitin_waf_server").pass()
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

=== TEST 1: set invalid waf server and route
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
                            "port": 18890
                        }
                    ],

                    "checks": {
                        "active": {
                            "type": "tcp",
                            "host": "localhost",
                            "timeout": 5,
                            "http_path": "/",
                            "healthy": {
                                "interval": 2,
                                "successes": 1
                            },
                            "unhealthy": {
                                "interval": 1,
                                "http_failures": 2
                            },
                            "req_headers": ["User-Agent: curl/7.29.0"]
                        }
                    }
                 }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            ngx.sleep(1)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "chaitin-waf": {
                                "upstream": {
                                   "servers": ["httpbun.org"]
                               },
                               "add_debug_header": true
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: pass
--- request
GET /hello
--- error_code: 200
--- response_body
hello world
--- error_log
--- response_headers
X-APISIX-CHAITIN-WAF: waf-err
X-APISIX-CHAITIN-WAF-ERROR: failed to connect to t1k server 127.0.0.1:18890: connection refused
--- response_headers_like
X-APISIX-CHAITIN-WAF-TIME:



=== TEST 3: set invalid waf server with valid waf server and healthcheck
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
                        },
                        {
                            "host": "127.0.0.1",
                            "port": 18890
                        }
                    ],

                    "checks": {
                        "active": {
                            "type": "tcp",
                            "host": "localhost",
                            "timeout": 5,
                            "http_path": "/",
                            "healthy": {
                                "interval": 2,
                                "successes": 1
                            },
                            "unhealthy": {
                                "interval": 1,
                                "http_failures": 2
                            },
                            "req_headers": ["User-Agent: curl/7.29.0"]
                        }
                    }
                 }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            ngx.sleep(1)
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "chaitin-waf": {
                                "upstream": {
                                   "servers": ["httpbun.org"]
                               },
                               "add_debug_header": true
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: pass
--- request
GET /hello
--- error_code: 200
--- response_body
hello world
--- error_log
--- response_headers
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-STATUS: 200
X-APISIX-CHAITIN-WAF-ACTION: pass
--- response_headers_like
X-APISIX-CHAITIN-WAF-TIME:
