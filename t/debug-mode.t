use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

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
$yaml_config =~ s/enable_debug: false/enable_debug: true/;


run_tests;

__DATA__

=== TEST 1: loaded plugin
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.3)
            ngx.say("done")
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
done
--- grep_error_log eval
qr/loaded plugin and sort by priority: [-\d]+ name: [\w-]+/
--- grep_error_log_out
loaded plugin and sort by priority: 10000 name: serverless-pre-function
loaded plugin and sort by priority: 3000 name: ip-restriction
loaded plugin and sort by priority: 2599 name: openid-connect
loaded plugin and sort by priority: 2510 name: jwt-auth
loaded plugin and sort by priority: 2500 name: key-auth
loaded plugin and sort by priority: 1003 name: limit-conn
loaded plugin and sort by priority: 1002 name: limit-count
loaded plugin and sort by priority: 1001 name: limit-req
loaded plugin and sort by priority: 1000 name: node-status
loaded plugin and sort by priority: 506 name: grpc-transcode
loaded plugin and sort by priority: 500 name: prometheus
loaded plugin and sort by priority: 0 name: example-plugin
loaded plugin and sort by priority: -1000 name: zipkin
loaded plugin and sort by priority: -2000 name: serverless-post-function



=== TEST 2: set route(no plugin)
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
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- response_headers
Apisix-Plugins: no plugin
--- no_error_log
[error]



=== TEST 4: set route(one plugin)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            },
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- response_body
hello world
--- response_headers
Apisix-Plugins: limit-conn, limit-count
--- no_error_log
[error]
