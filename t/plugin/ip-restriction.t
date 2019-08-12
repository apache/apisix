use t::APISix 'no_plan';

repeat_each(1);
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
$yaml_config =~ s/- example-plugin/- ip-restriction/;

run_tests;


__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")
            local conf = {
                whitelist = {
                    "10.255.254.0/24",
                    "192.168.0.0/16"
                }
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("cjson").encode(conf))
        }
    }
--- request
GET /t
--- response_body
{"whitelist":["10.255.254.0\/24","192.168.0.0\/16"]}
--- no_error_log
[error]



=== TEST 2: empty conf
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")

            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "oneOf" in docuement at pointer "#"
done
--- no_error_log
[error]


=== TEST 3: empty CIDRs
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")

            local ok, err = plugin.check_schema({blacklist={}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "type" in docuement at pointer "#/blacklist"
done
--- no_error_log
[error]



=== TEST 4: whitelist and blacklist mutual exclusive
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ip-restriction")
            local ok, err = plugin.check_schema({whitelist={"172.17.40.0/24"}, blacklist={"10.255.0.0/16"}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "oneOf" in docuement at pointer "#"
done
--- no_error_log
[error]


=== TEST 5: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/server_port",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ip-restriction": {
                                 "whitelist": [
                                     "127.0.0.0/24"
                                 ]
                            }
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
--- yaml_config eval
$::yaml_config
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: hit route
--- request
GET /server_port
--- response_body_like eval
qr/1980/
--- no_error_log
[error]


=== TEST 7: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/server_port",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ip-restriction": {
                                 "blacklist": [
                                     "127.0.0.0/24"
                                 ]
                            }
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
--- yaml_config eval
$::yaml_config
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: hit route
--- request
GET /server_port
--- yaml_config eval
$::yaml_config
--- error_code: 403
--- response_body
{"message":"Your IP address is not allowed"}
--- no_error_log
[error]
