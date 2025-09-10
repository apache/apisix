use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
upstreams:
  - id: 1
    type: roundrobin
    nodes:
      "test.com:1980": 1
    checks:
      active:
        http_path: "/status"
        host: 127.0.0.1
        port: 1988
        healthy:
          interval: 1
          successes: 1
        unhealthy:
          interval: 1
          http_failures: 1
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: setup route with domain-based upstream
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream:
        type: roundrobin
        nodes:
            "test.com:1980": 1
        checks:
            active:
                http_path: "/status"
                host: 127.0.0.1
                port: 1988
                healthy:
                interval: 1
                successes: 1
                unhealthy:
                interval: 1
                http_failures: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            ngx.say("Route setup complete")
        }
    }
--- response_body
Route setup complete
--- timeout: 5



=== TEST 2: healthchecker created on first request with initial DNS resolution
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream:
        type: roundrobin
        nodes:
            "test.com:1980": 1
        checks:
            active:
                http_path: "/status"
                host: 127.0.0.1
                port: 1988
                healthy:
                interval: 1
                successes: 1
                unhealthy:
                interval: 1
                http_failures: 1
--- config
    location /t {
        content_by_lua_block {
            -- Mock DNS resolution to return initial IP
            local utils = require("apisix.core.utils")
            utils.dns_parse = function(domain)
                if domain == "test.com" then
                    return {address = "127.0.0.1"}
                end
                error("unknown domain: " .. domain)
            end

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(4)
            ngx.say(res.status)
        }
    }
--- response_body
200
--- grep_error_log eval
qr/create new checker/
--- grep_error_log_out eval
[
qr/create new checker/,
]
--- timeout: 10
