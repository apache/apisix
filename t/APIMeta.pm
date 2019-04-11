package t::APIMeta;

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
    lua_package_path "$pwd/lua/?.lua;;";

    init_by_lua_block {
        require "resty.core"
    }
_EOC_

    $block->set_value("http_config", $http_config);

    my $user_files = $block->user_files;
    $user_files .= <<_EOC_;
>>> ../conf/config.yaml
$yaml_config
_EOC_

    $block->set_value("user_files", $user_files);

    $block;
});

1;
