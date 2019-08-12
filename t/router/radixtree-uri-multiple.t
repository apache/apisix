use t::APISix 'no_plan';

repeat_each(1);
log_level('info');
worker_connections(256);
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
$yaml_config =~ s/http: 'r3_uri'/http: 'radixtree_uri'/;

run_tests();

__DATA__

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/server_port"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: set route(id: 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1981": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/server_port/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: set route(id: 3)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/server_port/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: /not_found
--- request
GET /not_found
--- yaml_config eval: $::yaml_config
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 5: hit route 1
--- request
GET /server_port
--- yaml_config eval: $::yaml_config
--- response_body eval
qr/1980/
--- no_error_log
[error]



=== TEST 6: hit route 2
--- request
GET /server_port/route2
--- yaml_config eval: $::yaml_config
--- response_body eval
qr/1981/
--- no_error_log
[error]



=== TEST 7: hit route 3
--- request
GET /server_port/hello
--- yaml_config eval: $::yaml_config
--- response_body eval
qr/1982/
--- no_error_log
[error]



=== TEST 8: delete route(id: 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: delete route(id: 3)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                 ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
