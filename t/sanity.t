# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(1);
log_level('warn');

my $pwd = cwd();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // '';
    $http_config .= <<_EOC_;
    lua_package_path "$pwd/lua/?.lua;;";

    init_by_lua_block {
        require "resty.core"
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

plan tests => blocks() * repeat_each() * 2;

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local apimeta = require("apimeta")
            apimeta.access()
        }
    }
--- request
GET /t
--- error_code: 404
--- response_body_like eval
qr/404 Not Found/
