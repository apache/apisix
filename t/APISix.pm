package t::APISix;

use lib 'lib';
use Cwd qw(cwd);
use Test::Nginx::Socket::Lua::Stream -Base;

my $pwd = cwd();

sub read_file($) {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

my $yaml_config = read_file("conf/config.yaml");

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // '';
    $http_config .= <<_EOC_;
    lua_package_path "$pwd/lua/?.lua;/usr/share/lua/5.1/?.lua;;";

    init_by_lua_block {
        require "resty.core"
        apisix = require("apisix")
        apisix.init()
    }

    init_worker_by_lua_block {
        require("apisix").init_worker()
    }
_EOC_

    $block->set_value("http_config", $http_config);

    my $config = $block->config;
    if (!$config) {
    $config .= <<_EOC_;
        location / {
            rewrite_by_lua_block {
                apisix.rewrite_phase()
            }

            access_by_lua_block {
                apisix.access_phase()
            }

            header_filter_by_lua_block {
                apisix.header_filter_phase()
            }

            log_by_lua_block {
                apisix.log_phase()
            }
        }
_EOC_
    }

    $block->set_value("config", $config);

    my $user_yaml_config = $block->yaml_config;
    if ($user_yaml_config) {
        $yaml_config = $user_yaml_config;
    }

    my $user_files = $block->user_files;
    $user_files .= <<_EOC_;
>>> ../conf/config.yaml
$yaml_config
_EOC_

    $block->set_value("user_files", $user_files);

    $block;
});

1;
