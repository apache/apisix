package t::APISix;

use lib 'lib';
use Cwd qw(cwd);
use Test::Nginx::Socket::Lua::Stream -Base;

repeat_each(1);
log_level('info');
no_long_string();
no_shuffle();

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

    my $init_by_lua_block = $block->init_by_lua_block // <<_EOC_;
    require "resty.core"
    apisix = require("apisix")
    apisix.init()
_EOC_

    my $http_config = $block->http_config // '';
    $http_config .= <<_EOC_;
    lua_package_path "$pwd/lua/?.lua;$pwd/t/?.lua;/usr/share/lua/5.1/?.lua;;";
    lua_package_cpath '/usr/lib64/lua/5.1/?.so;;';

    lua_shared_dict plugin-limit-req 10m;
    lua_shared_dict plugin-limit-count 10m;
    lua_shared_dict plugin-limit-conn 10m;
    lua_shared_dict prometheus-metrics 10m;

    resolver ipv6=off local=on;
    resolver_timeout 5;

    lua_socket_log_errors off;

    upstream apisix_backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            apisix.balancer_phase()
        }

        keepalive 32;
    }

    init_by_lua_block {
        $init_by_lua_block
    }

    init_worker_by_lua_block {
        require("apisix").init_worker()
    }

    server {
        listen 1980;
        listen 1981;
        listen 1982;

        location / {
            content_by_lua_block {
                require("lib.server").go()
            }
        }
    }

_EOC_

    $block->set_value("http_config", $http_config);

    my $wait_etcd_sync = $block->wait_etcd_sync // 0.1;

    my $config = $block->config // '';
    $config .= <<_EOC_;
        location = /apisix/nginx_status {
            internal;
            access_log off;
            stub_status;
        }

        location /apisix/admin {
            content_by_lua_block {
                apisix.admin()
            }
        }

        location / {
            set \$upstream_scheme             'http';
            set \$upstream_host               \$host;
            set \$upstream_upgrade            '';
            set \$upstream_connection         '';
            set \$upstream_uri                '';

            access_by_lua_block {
                -- wait for etcd sync
                ngx.sleep($wait_etcd_sync)
                apisix.access_phase()
            }

            proxy_http_version 1.1;
            proxy_set_header   Host              \$upstream_host;
            proxy_set_header   Upgrade           \$upstream_upgrade;
            proxy_set_header   Connection        \$upstream_connection;
            proxy_set_header   X-Real-IP         \$remote_addr;
            proxy_pass_header  Server;
            proxy_pass_header  Date;
            proxy_pass         \$upstream_scheme://apisix_backend\$upstream_uri;

            header_filter_by_lua_block {
                apisix.header_filter_phase()
            }

            log_by_lua_block {
                apisix.log_phase()
            }
        }
_EOC_

    $block->set_value("config", $config);

    my $user_yaml_config = $block->yaml_config // $yaml_config;

    my $user_files = $block->user_files;
    $user_files .= <<_EOC_;
>>> ../conf/config.yaml
$user_yaml_config
_EOC_

    $block->set_value("user_files", $user_files);

    $block;
});

1;
