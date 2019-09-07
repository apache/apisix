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
$yaml_config =~ s/http: 'radixtree_uri'/ssl: 'r3_uri'/;

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
                        "methods": ["GET"],
                        "uri": "/hello",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: /not_found
--- request
GET /not_found
--- yaml_config eval: $::yaml_config
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 3: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- no_error_log
[error]



=== TEST 4: set route(id: 1)
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
                        "uri": "/hello{:1?}"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: hit routes：/hello
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- no_error_log
[error]



=== TEST 6: hit routes: /hello1
--- request
GET /hello1
--- yaml_config eval: $::yaml_config
--- response_body
hello1 world
--- no_error_log
[error]



=== TEST 7: hit routes: /hello2
--- request
GET /hello2
--- yaml_config eval: $::yaml_config
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]
