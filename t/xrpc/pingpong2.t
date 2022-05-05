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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
xrpc:
  protocols:
    - name: pingpong
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    my $config = $block->config // <<_EOC_;
    location /t {
        content_by_lua_block {
            ngx.req.read_body()
            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(503)
            end

            local bytes, err = sock:send(ngx.req.get_body_data())
            if not bytes then
                ngx.log(ngx.ERR, "send stream request error: ", err)
                return ngx.exit(503)
            end
            while true do
                local data, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
                ngx.print(data)
            end
        }
    }
_EOC_

    $block->set_value("config", $config);

    my $stream_upstream_code = $block->stream_upstream_code // <<_EOC_;
            local sock = ngx.req.socket(true)
            sock:settimeout(10)
            while true do
                local data = sock:receiveany(4096)
                if not data then
                    return
                end
                sock:send(data)
            end
_EOC_

    $block->set_value("stream_upstream_code", $stream_upstream_code);

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]\nRPC is not finished");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: init
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "pingpong"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1995"] = 1
                        },
                        type = "roundrobin"
                    }
                }
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



=== TEST 2: check the default timeout
--- request eval
"POST /t
" .
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- response_body eval
"pp\x02\x00\x00\x00\x00\x00\x00\x03ABC"
--- error_log
stream lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 60000
stream lua tcp socket read timeout: 60000
--- log_level: debug
--- stream_conf_enable
