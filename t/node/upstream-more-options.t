BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set route(more upstream options)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/old_uri",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "scheme": "http",
                        "host": "foo.com",
                        "upgrade": "upgrade.com",
                        "connection": "connection.com",
                        "uri": "/uri"
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
--- no_error_log
[error]



=== TEST 2: hit routes
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/old_uri"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end

            if res.status >= 300 then
                ngx.status = res.status
            end
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- response_body
uri: /uri
host: foo.com
x-real-ip: 127.0.0.1
connection: connection.com
upgrade: upgrade.com
user-agent: lua-resty-http/0.13 (Lua) ngx_lua/10015
--- no_error_log
[error]
