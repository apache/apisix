BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISix 'no_plan';

master_on();
repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

run_tests();

__DATA__

=== TEST 1: set route(two healthy upstream nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
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
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 2: hit routes (two healthy nodes)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(2) -- wait for sync

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("cjson").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":6,"port":"1981"},{"count":6,"port":"1980"}]
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out
--- timeout: 6



=== TEST 3: set route(two upstream node: one healthy + one unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1970": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
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
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 4: hit routes (two upstream node: one healthy + one unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            end

            ngx.sleep(2.5)

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end

                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("cjson").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/\[error\].*/
--- grep_error_log_out eval
qr/Connection refused\) while connecting to upstream/
--- timeout: 10



=== TEST 5: chash route (two healthy nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "chash",
                        "nodes": {
                            "127.0.0.1:1981": 1,
                            "127.0.0.1:1980": 1
                        },
                        "key": "remote_addr",
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
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
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 6: hit routes (two healthy nodes)
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(2) -- wait for sync

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("cjson").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out
--- timeout: 6



=== TEST 7: chash route (upstream nodes: 1 healthy + 8 unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "chash",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1970": 1,
                            "127.0.0.1:1971": 1,
                            "127.0.0.1:1972": 1,
                            "127.0.0.1:1973": 1,
                            "127.0.0.1:1974": 1,
                            "127.0.0.1:1975": 1,
                            "127.0.0.1:1976": 1,
                            "127.0.0.1:1977": 1
                        },
                        "key": "remote_addr",
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
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
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 8: hit routes (upstream nodes: 1 healthy + 8 unhealthy)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            end

            ngx.sleep(2.5)

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end

                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("cjson").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out eval
qr/Connection refused\) while connecting to upstream/
--- timeout: 10



=== TEST 9: chash route (upstream nodes: 2 unhealthy)
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{"uri":"/server_port","upstream":{"type":"chash","nodes":{"127.0.0.1:1960":1,"127.0.0.1:1961":1},"key":"remote_addr","retries":3,"checks":{"active":{"http_path":"/status","host":"foo.com","healthy":{"interval":999,"successes":3},"unhealthy":{"interval":999,"http_failures":3}},"passive":{"healthy":{"http_statuses":[200,201],"successes":3},"unhealthy":{"http_statuses":[500],"http_failures":3,"tcp_failures":3}}}}}]]
        )

        if code >= 300 then
        ngx.status = code
        end
        ngx.say(body)
  }
}
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 10: hit routes (passive + retries)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri,
                    {method = "GET", keepalive = false}
                )
                ngx.say("res: ", res.status, " err: ", err)
            end
        }
    }
--- request
GET /t
--- response_body
res: 502 err: nil
res: 502 err: nil
--- grep_error_log eval
qr{\[error\].*while connecting to upstream.*}
--- grep_error_log_out eval
qr{.*http://127.0.0.1:1960/server_port.*
.*http://127.0.0.1:1960/server_port.*
.*http://127.0.0.1:1961/server_port.*
.*http://127.0.0.1:1961/server_port.*
.*http://127.0.0.1:1961/server_port.*}
--- timeout: 10
