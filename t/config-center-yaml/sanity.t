use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

sub read_file($) {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $yaml_config = read_file("conf/config.yaml");
$yaml_config =~ s/node_listen: 9080/node_listen: 1984/;
$yaml_config =~ s/enable_heartbeat: true/enable_heartbeat: false/;
$yaml_config =~ s/config_center: etcd/config_center: yaml/;

run_tests();

__DATA__

=== TEST 1: sanity
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        ngx.say("done")
    }
}
--- yaml_config eval: $::yaml_config
--- apisix_yaml
uri: /hello
upstream:
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
--- request
GET /t
--- response_body
done
--- error_log
use config_center: yaml
--- no_error_log
[error]
