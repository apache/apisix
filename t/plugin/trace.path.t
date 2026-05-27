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

=== TEST 1: create route with uri "/*"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/*",
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
        }
    }
--- response_body
done



=== TEST 2: match against pattern "/*"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local httpc = http.new()

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
    rate = 100,
    paths = {"/*"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/nohello"
            local res, err = httpc:request_uri(uri)
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:



=== TEST 3: match against pattern "/abc/*"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local httpc = http.new()

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
    rate = 100,
    paths = {"/abc/*"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/abc/hello"
            local res, err = httpc:request_uri(uri)
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:



=== TEST 4: match against pattern "/abc/*/cde"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local httpc = http.new()

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
    rate = 1,
    paths = {"/abc/*/cde"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/abc/foo/cde"
            -- send 100 requests, 1 will match randomly
            for i = 1, 100 do
                local res, err = httpc:request_uri(uri)
            end

            -- no match
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/abc/hello"
            for i = 1, 100 do
                local res, err = httpc:request_uri(uri)
            end
        }
    }
--- timeout: 40
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:



=== TEST 5: match against pattern "/*/cde"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local httpc = http.new()

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
    rate = 1,
    paths = {"/*/cde"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foo/cde"
            -- send 100 requests, 1 will match randomly
            for i = 1, 100 do
                local res, err = httpc:request_uri(uri)
            end

            -- no match
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/abc/hello"
            for i = 1, 100 do
                local res, err = httpc:request_uri(uri)
            end
        }
    }
--- timeout: 40
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:
