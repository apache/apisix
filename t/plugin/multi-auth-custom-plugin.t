use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");


add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_init_by_lua_start = <<_EOC_;
require "agent.hook";
_EOC_

    if (!defined $block->extra_init_by_lua_start) {
        $block->set_value("extra_init_by_lua_start", $extra_init_by_lua_start);
    }

    my $http_config = $block->http_config // <<_EOC_;
lua_shared_dict config 5m;
_EOC_
    $block->set_value("http_config", $http_config);

    my $extra_init_by_lua = <<_EOC_;
    local server = require("lib.server")
    server.api_dataplane_heartbeat = function()
        ngx.say("{}")
    end

    server.api_dataplane_metrics = function()
    end

    server.apisix_prometheus_metrics = function()
        ngx.say('apisix_http_status{code="200",route="httpbin",matched_uri="/*",matched_host="nic.httpbin.org",service="",consumer="",node="172.30.5.135"} 61')
    end
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);

    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
plugin_attr:
  prometheus:
    export_addr:
      port: 1980
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});
run_tests;

__DATA__

=== TEST 1: API7EE custom auth plugin in multi-auth plugin should work
--- extra_init_by_lua_start
--- extra_yaml_config
apisix:
  lua_module_hook: ""
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin").test
        local util = require("apisix.cli.util")

        local custom_plugin = util.read_file("t/assets/custom-auth-plugin.lua")
        local key = "/custom_plugins/custom-key-auth"
        local val = {
            name = "custom-key-auth",
            content = custom_plugin
        }
        local _, err = core.etcd.set(key, val)
        if err then
            ngx.say(err)
            return
        end

        local code, body = t('/apisix/admin/consumers',
            ngx.HTTP_PUT,
            [[{
                "username": "foo",
                "plugins": {
                    "basic-auth": {
                        "username": "foo",
                        "password": "bar"
                    },
                    "custom-key-auth": {
                        "key": "auth-one"
                    }
                }
            }]]
        )
        if code >= 300 then
            ngx.status = code
            return
        end

        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
            [[{
                "plugins": {
                    "multi-auth": {
                        "auth_plugins": [
                            {
                                "basic-auth": {}
                            },
                            {
                                "custom-key-auth": {
                                    "hide_credentials": true
                                }
                            },
                            {
                                "jwt-auth": {
                                    "hide_credentials": true
                                }
                            }
                        ]
                    }
                },
                "upstream": {
                    "nodes": {
                        "127.0.0.1:1980": 1
                    },
                    "type": "roundrobin"
                },
                "uri": "/hello"
            }]]
            )

        if code >= 300 then
            ngx.status = code
            return
        end

-- verify custom-key-auth

    -- verify correct APIKEY

        local code, body = t("/hello", ngx.HTTP_GET, nil, nil, {
            apikey = "auth-one"
        })

        if code >= 300 then
            ngx.status = code
            return
        end

    -- verify incorrect APIKEY

        local code, body = t("/hello", ngx.HTTP_GET, nil, nil, {
            apikey = "not-auth-one"
        })

        if code ~= 401 then
            ngx.status = 503
            return
        end

--------------------------------------------

-- verify basic-auth

    -- verify correct Authorization header

        local code, body = t("/hello", ngx.HTTP_GET, nil, nil, {
            Authorization = "Basic Zm9vOmJhcg=="
        })

        if code >= 300 then
            ngx.status = code
            return
        end

    -- verify incorrect Authorization header

        local code, body = t("/hello", ngx.HTTP_GET, nil, nil, {
            Authorization = "Basic wrong-token"
        })

        if code ~= 401 then
            ngx.status = 503
            return
        end
        ngx.say("done")
    }
}
--- request
GET /t
--- response_body
done
