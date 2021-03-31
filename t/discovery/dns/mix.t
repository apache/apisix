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
BEGIN {
    $ENV{CUSTOM_DNS_SERVER} = "127.0.0.1:1053";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
discovery:                        # service discovery center
    dns:
        servers:
            - "127.0.0.1:1053"
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
routes:
  -
    id: 1
    uris:
        - /hello
    upstream_id: 1
  -
    id: 2
    uris:
        - /hello_chunked
    upstream_id: 2
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: mix cache between discovery & global resolver
--- log_level: debug
--- apisix_yaml
upstreams:
    -
        id: 1
        nodes:
            ttl.1s.test.local:1980: 1
        type: roundrobin
    -
        id: 2
        service_name: "ttl.1s.test.local:1980"
        discovery_type: dns
        type: roundrobin
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri1 = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local uri2 = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello_chunked"
            for i = 1, 2 do
                for j = 1, 3 do
                    local httpc = http.new()
                    local res, err
                    if j % 2 ~= 0 then
                        res, err = httpc:request_uri(uri1, {method = "GET"})
                    else
                        res, err = httpc:request_uri(uri2, {method = "GET"})
                    end

                    if not res or res.body ~= "hello world\n" then
                        ngx.say(err)
                        return
                    end
                end

                if i < 2 then
                    ngx.sleep(1.1)
                end
            end
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/connect to 127.0.0.1:1053/
--- grep_error_log_out
connect to 127.0.0.1:1053
connect to 127.0.0.1:1053
connect to 127.0.0.1:1053
connect to 127.0.0.1:1053
