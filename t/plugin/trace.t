use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

my $user_yaml_config = <<_EOC_;
plugins:
  - toolset
  - serverless-post-function
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: create route
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
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("done")

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            local old = file:read("*all")
            file:write([[
return {
  trace = {
    rate = 1
  }
}
]])
            file:close()
        }
    }
--- response_body
done



=== TEST 2: test table layout
--- request
GET /hello
--- error_log
| Role     | Phase                     | Timespan | Start time              |



=== TEST 3: remove plugin and send request after plugin reload
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local conf, err = io.open("t/servroot/conf/config.yaml", "w+")
            if not conf then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end

            -- yaml config to remove trace plugin
            local config = "deployment:\n  role: traditional\n  role_traditional:\n    config_provider: etcd\n  admin:\n    admin_key: null\napisix:\n  node_listen: 1984\n  proxy_mode: http&stream\n  stream_proxy:\n    tcp:\n      - 9100\n  enable_resolv_search_opt: false\nplugins:\n  - serverless-post-function\n"
            conf:write(config)

            -- reload plugins
            local code, _, org_body = t('/apisix/admin/plugins/reload', ngx.HTTP_PUT)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
            conf:close()
        }
    }
--- no_error_log
trace:



=== TEST 4: test match_route
--- request
GET /hello
--- error_log eval
qr/\| APISIX\s{3}\| \\_match_route\s{13}\| \d+ms\s+\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.(\d+|000) \|/



=== TEST 5: test access
--- request
GET /hello
--- error_log eval
qr/\| APISIX\s{3}\| access\s{20}\| \d+ms\s+\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.(\d+|000) \|/



=== TEST 6: test balancer
--- request
GET /hello
--- error_log eval
qr/\| APISIX\s{3}\| balancer\s{18}\| \d+ms\s+\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.(\d+|000) \|/



=== TEST 7: test header_filter
--- request
GET /hello
--- error_log eval
qr/\| APISIX\s{3}\| header_filter\s{13}\| \d+ms\s+\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.(\d+|000) \|/



=== TEST 8: test body_filter
--- request
GET /hello
--- error_log eval
qr/\| APISIX\s{3}\| body_filter\s{15}\| \d+ms\s+\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.(\d+|000) \|/



=== TEST 9: test log
--- request
GET /hello
--- error_log eval
qr/\| APISIX\s{3}\| log\s{23}\| \d+ms\s+\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.(\d+|000) \|/



=== TEST 10: test upstream
--- request
GET /hello
--- error_log eval
qr/\| Upstream \| upstream \(req \+ response\) \| \d+ms\s+\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.(\d+|000) \|/



=== TEST 11: test client
--- request
GET /hello
--- error_log eval
qr/\| Client   \| response                  \| \d+ms\s+\| \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.(\d+|000) \|/



=== TEST 12: test failed match route
--- request
GET /wrong_uri_hello
--- error_code: 404
--- error_log
| Role     | Phase                     | Timespan | Start time              |
--- no_error_log
| balancer
| upstream (req + response)
| response



=== TEST 13: check rate
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")


            -- prepare trace config with rate = 1
            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            file:write([[
return {
  trace = {
    rate = 1
  }
}
]])
            file:close()


            ngx.sleep(2)


            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()

            -- send 2 requests, since rate = 1 only first will match
            local res, err = httpc:request_uri(uri)
            local res, err = httpc:request_uri(uri)
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:



=== TEST 14: check rate (rate = 3)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            -- prepare config with rate = 3
            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            file:write("return { trace = {rate = 3}}")
            file:close()


            ngx.sleep(2)


            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()

            -- send 100 requests, 3 will match randomly
            for i = 1, 100 do
                local res, err = httpc:request_uri(uri)
            end
        }
    }
--- timeout: 20
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:
trace:
trace:



=== TEST 15: check rate: `rate = nil` should log all requests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            -- prepare config with rate = nil
            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            file:write("return { trace = {rate = nil}}")
            file:close()


            ngx.sleep(2)


            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()

            -- send 5 requests
            for i = 1, 5 do
                local res, err = httpc:request_uri(uri)
            end
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:
trace:
trace:
trace:
trace:



=== TEST 16: check rate: `type(rate) ~= "number"`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            file:write("return { trace = {rate = \"not a number\"}}")
            file:close()


            ngx.sleep(2)


            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()

            -- send 5 requests
            for i = 1, 5 do
                local res, err = httpc:request_uri(uri)
            end
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:
trace:
trace:
trace:
trace:



=== TEST 17: request_uri not defined in config should not trace
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            file:write("return { trace = { paths = {\"/nohello\"}}}")
            file:close()


            ngx.sleep(2)


            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()

            local res, err = httpc:request_uri(uri)
        }
    }
--- no_error_log
trace:



=== TEST 18: only request_uri defined in config should trace
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            file:write("return { trace = {paths = {\"/nohello\"}}}")
            file:close()


            ngx.sleep(2)


            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/nohello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:



=== TEST 19: requests taking less than trace_conf.timespan_threshold should not log
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            file:write("return { trace = { timespan_threshold = 60 } }")
            file:close()


            ngx.sleep(2)


            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/nohello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
        }
    }
--- no_error_log
trace:
