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
    $ENV{REDIS_NODE_0} = "127.0.0.1:5000";
    $ENV{REDIS_NODE_1} = "127.0.0.1:5001";
}

use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: modified redis script, cost == 2
--- config
    location /t {
        content_by_lua_block {
            local conf = {
                redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"},
                redis_cluster_name = "redis-cluster-1",
                redis_cluster_ssl = false,
                redis_timeout = 1000,
                key_type = "var",
                time_window = 60,
                show_limit_quota_header = true,
                allow_degradation = false,
                key = "remote_addr",
                rejected_code = 503,
                count = 3,
                policy = "redis-cluster",
                redis_cluster_ssl_verify = false
            }

            local lim_count_redis_cluster = require("apisix.plugins.limit-count.limit-count-redis-cluster")
            local lim = lim_count_redis_cluster.new("limit-count", 3, 60, conf)
            local uri = ngx.var.uri
            local _, remaining, _ = lim:incoming(uri, 2)

            ngx.say("remaining: ", remaining)
        }
    }
--- response_body
remaining: 1



=== TEST 2: set route, with redis_cluster_nodes as environement variables and redis_cluster_name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis-cluster",
                            "redis_timeout": 1001,
                            "redis_cluster_nodes": [
                                "$ENV://REDIS_NODE_0",
                                "$ENV://REDIS_NODE_1"
                            ],
                            "redis_cluster_name": "redis-cluster-1"
                        }
                    },
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
--- response_body
passed



=== TEST 3: up the limit with environment variables for redis_cluster_nodes
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]
