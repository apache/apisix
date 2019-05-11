use t::APIMeta 'no_plan';

repeat_each(2);

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local encode_json = require "cjson.safe" .encode
            local config = require("apimeta.core.config").local_conf()

            ngx.say("etcd host: ", config.etcd.host)
            ngx.say("first plugin: ", encode_json(config.plugins[1]))
        }
    }
--- request
GET /t
--- response_body
etcd host: http://127.0.0.1:2379
first plugin: "example-plugin"
