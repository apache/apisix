use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("stream_conf_enable", 1);

    if (!defined $block->extra_stream_config) {
        my $stream_config = <<_EOC_;
    server {
        listen unix:\$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({})
        }
    }

_EOC_
        $block->set_value("extra_stream_config", $stream_config);
    }

    my $unix_socket_path = $ENV{"TEST_NGINX_HTML_DIR"} . "/nginx.sock";
    my $cmd = $block->ext_plugin_cmd // "['sleep', '5s']";
    my $extra_yaml_config = <<_EOC_;
ext-plugin:
    path_for_test: $unix_socket_path
    cmd: $cmd
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: rewrite header
--- extra_stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local ext = require("lib.ext-plugin")
            ext.go({rewrite = true})
            local headers = ngx.req.get_headers()
            ngx.say(headers["x-change"])
            headers["x-change"] == "bar"
        }
    }
--- request
GET /hello
--- more_headers
x-change: foo
--- response_body chomp
cat
--- error_code: 405