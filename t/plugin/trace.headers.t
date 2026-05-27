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

            -- make all requests trace (rate = 100)
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
    hosts = {"*.com"}
  }
}
]])
            file:close()
        }
    }
--- response_body
done



=== TEST 2: check if observability tracing services headers take effect
--- request
GET /hello
--- more_headers
x-request-id: qewh42384238r09
sw8: 2385248054058
traceparent: 23852iwjefuisu489
x-b3-traceid: oshe98ru348
--- error_log
x-request-id: qewh42384238r09
sw8: 2385248054058
traceparent: 23852iwjefuisu489
x-b3-traceid: oshe98ru348
trace:
| Role     | Phase                     | Timespan | Start time              |



=== TEST 3: trace vars
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
     vars = {"foo", "request_method"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {headers = { ["foo"] = "bar" }})
        }
    }
--- error_log
request_method: GET
trace:
| Role     | Phase                     | Timespan | Start time              |
--- no_error_log
foo:



=== TEST 4: trace log contains uuid when no headers are found and `gen_uid = true`
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
    gen_uid = true
  }
}
]])
            file:close()


            ngx.sleep(2)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri)
        }
    }
--- error_log
uuid:
trace:
| Role     | Phase                     | Timespan | Start time              |
--- no_error_log
x-request-id:
sw8:
traceparent:
x-b3-traceid:



=== TEST 5: trace doesn't contain uid if traceable headers are present
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
    gen_uid = true,
    vars = {"uri"}
  }

}
]])
            file:close()


            ngx.sleep(2)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {headers = { ["foo"] = "bar" }}) -- header foo need not be traced
        }
    }
--- error_log
trace:
| Role     | Phase                     | Timespan | Start time              |
--- no_error_log
x-request-id:
sw8:
traceparent:
x-b3-traceid:
uid:
