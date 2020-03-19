#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
package t::APISIX;

use lib 'lib';
use Cwd qw(cwd);
use Test::Nginx::Socket::Lua::Stream -Base;

repeat_each(1);
log_level('info');
no_long_string();
no_shuffle();
worker_connections(128);

my $apisix_home = $ENV{APISIX_HOME} || cwd();

sub read_file($) {
    my $infile = shift;
    open my $in, "$apisix_home/$infile"
        or die "cannot open $infile for reading: $!";
    my $data = do { local $/; <$in> };
    close $in;
    $data;
}

my $yaml_config = read_file("conf/config.yaml");
my $ssl_crt = read_file("conf/cert/apisix.crt");
my $ssl_key = read_file("conf/cert/apisix.key");
$yaml_config =~ s/node_listen: 9080/node_listen: 1984/;
$yaml_config =~ s/enable_heartbeat: true/enable_heartbeat: false/;
$yaml_config =~ s/admin_key:/admin_key_useless:/;

my $profile = $ENV{"APISIX_PROFILE"};


my $apisix_file;
my $debug_file;
my $config_file;
if ($profile) {
    $apisix_file = "apisix-$profile.yaml";
    $debug_file = "debug-$profile.yaml";
    $config_file = "config-$profile.yaml";
} else {
    $apisix_file = "apisix.yaml";
    $debug_file = "debug.yaml";
    $config_file = "config.yaml";
}


add_block_preprocessor(sub {
    my ($block) = @_;
    my $wait_etcd_sync = $block->wait_etcd_sync // 0.1;

    my $main_config = $block->main_config // <<_EOC_;
worker_rlimit_core  500M;
working_directory   $apisix_home;
env APISIX_PROFILE;
_EOC_

    $block->set_value("main_config", $main_config);

    my $stream_enable = $block->stream_enable;
    my $stream_config = $block->stream_config // <<_EOC_;
    lua_package_path "$apisix_home/deps/share/lua/5.1/?.lua;$apisix_home/lua/?.lua;$apisix_home/t/?.lua;./?.lua;;";
    lua_package_cpath "$apisix_home/deps/lib/lua/5.1/?.so;$apisix_home/deps/lib64/lua/5.1/?.so;./?.so;;";

    lua_socket_log_errors off;

    upstream apisix_backend {
        server 127.0.0.1:1900;
        balancer_by_lua_block {
            apisix.stream_balancer_phase()
        }
    }

    init_by_lua_block {
        if os.getenv("APISIX_ENABLE_LUACOV") == "1" then
            require("luacov.runner")("t/apisix.luacov")
            jit.off()
        end

        require "resty.core"

        apisix = require("apisix")
        apisix.stream_init()
    }

    init_worker_by_lua_block {
        apisix.stream_init_worker()
    }

    # fake server, only for test
    server {
        listen 1995;

        content_by_lua_block {
            local sock = ngx.req.socket()
            local data = sock:receive("1")
            ngx.say("hello world")
        }
    }
_EOC_

    if (defined $stream_enable) {
        $block->set_value("stream_config", $stream_config);
    }

    my $stream_server_config = $block->stream_server_config // <<_EOC_;
    preread_by_lua_block {
        -- wait for etcd sync
        ngx.sleep($wait_etcd_sync)
        apisix.stream_preread_phase()
    }

    proxy_pass apisix_backend;

    log_by_lua_block {
        apisix.stream_log_phase()
    }
_EOC_

    if (defined $stream_enable) {
        $block->set_value("stream_server_config", $stream_server_config);
    }

    my $init_by_lua_block = $block->init_by_lua_block // <<_EOC_;
    if os.getenv("APISIX_ENABLE_LUACOV") == "1" then
        require("luacov.runner")("t/apisix.luacov")
        jit.off()
    end

    require "resty.core"

    apisix = require("apisix")
    apisix.http_init()
_EOC_

    my $http_config = $block->http_config // '';
    $http_config .= <<_EOC_;
    lua_package_path "$apisix_home/deps/share/lua/5.1/?.lua;$apisix_home/lua/?.lua;$apisix_home/t/?.lua;./?.lua;;";
    lua_package_cpath "$apisix_home/deps/lib/lua/5.1/?.so;$apisix_home/deps/lib64/lua/5.1/?.so;./?.so;;";

    lua_shared_dict plugin-limit-req     10m;
    lua_shared_dict plugin-limit-count   10m;
    lua_shared_dict plugin-limit-conn    10m;
    lua_shared_dict prometheus-metrics   10m;
    lua_shared_dict upstream-healthcheck 32m;
    lua_shared_dict worker-events        10m;

    resolver 8.8.8.8 114.114.114.114 ipv6=off;
    resolver_timeout 5;

    underscores_in_headers on;
    lua_socket_log_errors off;

    upstream apisix_backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            apisix.http_balancer_phase()
        }

        keepalive 32;
    }

    init_by_lua_block {
        $init_by_lua_block
    }

    init_worker_by_lua_block {
        require("apisix").http_init_worker()
    }

    # fake server, only for test
    server {
        listen 1980;
        listen 1981;
        listen 1982;
        listen 5044;

_EOC_

    my $ipv6_fake_server = "";
    if (defined $block->listen_ipv6) {
        $ipv6_fake_server = "listen \[::1\]:1980;";
    }

    $http_config .= <<_EOC_;
        $ipv6_fake_server
        server_tokens off;

        location / {
            content_by_lua_block {
                require("lib.server").go()
            }

            more_clear_headers Date;
        }
    }

    server {
        listen 1983 ssl;
        ssl_certificate             cert/apisix.crt;
        ssl_certificate_key         cert/apisix.key;
        lua_ssl_trusted_certificate cert/apisix.crt;

        server_tokens off;

        location / {
            content_by_lua_block {
                require("lib.server").go()
            }

            more_clear_headers Date;
        }
    }

_EOC_

    $block->set_value("http_config", $http_config);

    my $TEST_NGINX_HTML_DIR = $ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
    my $ipv6_listen_conf = '';
    if (defined $block->listen_ipv6) {
        $ipv6_listen_conf = "listen \[::1\]:12345;"
    }

    my $config = $block->config // '';
    $config .= <<_EOC_;
        $ipv6_listen_conf

        ssl_certificate             cert/apisix.crt;
        ssl_certificate_key         cert/apisix.key;
        lua_ssl_trusted_certificate cert/apisix.crt;

        ssl_certificate_by_lua_block {
            apisix.http_ssl_phase()
        }

        location = /apisix/nginx_status {
            allow 127.0.0.0/24;
            access_log off;
            stub_status;
        }

        location /apisix/admin {
            content_by_lua_block {
                apisix.http_admin()
            }
        }

        location / {
            set \$upstream_mirror_host        '';
            set \$upstream_scheme             'http';
            set \$upstream_host               \$host;
            set \$upstream_upgrade            '';
            set \$upstream_connection         '';
            set \$upstream_uri                '';

            set \$upstream_cache_zone            off;
            set \$upstream_cache_key             '';
            set \$upstream_cache_bypass          '';
            set \$upstream_no_cache              '';
            set \$upstream_hdr_expires           '';
            set \$upstream_hdr_cache_control     '';

            proxy_cache                         \$upstream_cache_zone;
            proxy_cache_valid                   any 10s;
            proxy_cache_min_uses                1;
            proxy_cache_methods                 GET HEAD;
            proxy_cache_lock_timeout            5s;
            proxy_cache_use_stale               off;
            proxy_cache_key                     \$upstream_cache_key;
            proxy_no_cache                      \$upstream_no_cache;
            proxy_cache_bypass                  \$upstream_cache_bypass;

            proxy_hide_header                   Cache-Control;
            proxy_hide_header                   Expires;
            add_header      Cache-Control       \$upstream_hdr_cache_control;
            add_header      Expires             \$upstream_hdr_expires;
            add_header      Apisix-Cache-Status \$upstream_cache_status always;

            access_by_lua_block {
                -- wait for etcd sync
                ngx.sleep($wait_etcd_sync)
                apisix.http_access_phase()
            }

            proxy_http_version 1.1;
            proxy_set_header   Host              \$upstream_host;
            proxy_set_header   Upgrade           \$upstream_upgrade;
            proxy_set_header   Connection        \$upstream_connection;
            proxy_set_header   X-Real-IP         \$remote_addr;
            proxy_pass_header  Server;
            proxy_pass_header  Date;
            proxy_pass         \$upstream_scheme://apisix_backend\$upstream_uri;
            mirror             /proxy_mirror;

            header_filter_by_lua_block {
                apisix.http_header_filter_phase()
            }

            body_filter_by_lua_block {
                apisix.http_body_filter_phase()
            }

            log_by_lua_block {
                apisix.http_log_phase()
            }
        }

        location \@grpc_pass {
            access_by_lua_block {
                apisix.grpc_access_phase()
            }

            grpc_set_header   Content-Type application/grpc;
            grpc_socket_keepalive on;
            grpc_pass         grpc://apisix_backend;

            header_filter_by_lua_block {
                apisix.http_header_filter_phase()
            }

            body_filter_by_lua_block {
                apisix.http_body_filter_phase()
            }

            log_by_lua_block {
                apisix.http_log_phase()
            }
        }

        location = /proxy_mirror {
            internal;

            if (\$upstream_mirror_host = "") {
                return 200;
            }

            proxy_pass \$upstream_mirror_host\$request_uri;
        }
_EOC_

    $block->set_value("config", $config);

    my $user_apisix_yaml = $block->apisix_yaml // "";
    if ($user_apisix_yaml) {
        $user_apisix_yaml = <<_EOC_;
>>> ../conf/$apisix_file
$user_apisix_yaml
_EOC_
    }

    my $user_yaml_config = $block->yaml_config // $yaml_config;
    my $user_debug_config = $block->debug_config // "";

    my $user_files = $block->user_files;
    $user_files .= <<_EOC_;
>>> ../conf/$debug_file
$user_debug_config
>>> ../conf/$config_file
$user_yaml_config
>>> ../conf/cert/apisix.crt
$ssl_crt
>>> ../conf/cert/apisix.key
$ssl_key
$user_apisix_yaml
_EOC_

    $block->set_value("user_files", $user_files);

    $block;
});

1;
