use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- grep_error_log eval
qr/loaded plugin and sort by priority: [-\d]+ name: [\w-]+/
--- grep_error_log_out
loaded plugin and sort by priority: 2510 name: jwt-auth
loaded plugin and sort by priority: 2500 name: key-auth
loaded plugin and sort by priority: 1003 name: limit-conn
loaded plugin and sort by priority: 1002 name: limit-count
loaded plugin and sort by priority: 1001 name: limit-req
loaded plugin and sort by priority: 1000 name: node-status
loaded plugin and sort by priority: 500 name: prometheus
loaded plugin and sort by priority: 0 name: example-plugin
loaded plugin and sort by priority: -1000 name: zipkin
