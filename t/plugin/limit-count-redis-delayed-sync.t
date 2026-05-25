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
use t::APISIX 'no_plan';

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

    my $extra_init_worker_by_lua = $block->extra_init_worker_by_lua // "";
    $extra_init_worker_by_lua .= <<_EOC_;
        require("lib.test_redis").flush_all()
_EOC_

    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);
});

run_tests;

__DATA__

=== TEST 1: setup routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local apis = {
                {
                    uri = "/apisix/admin/upstreams/localhost_1980",
                    body = [[{
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }]],
                },
                {
                    uri = "/apisix/admin/routes/hello",
                    body = [[{
                        "uri": "/hello",
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "key_type": "var",
                                "key": "arg_key",
                                "policy": "redis",
                                "redis_host": "127.0.0.1",
                                "window_type": "sliding",
                                "sync_interval": 0.2
                            }
                        },
                        "upstream_id": "localhost_1980"
                    }]],
                },
                {
                    uri = "/apisix/admin/routes/hello1",
                    body = [[{
                        "uri": "/hello1",
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "policy": "redis-cluster",
                                "redis_cluster_nodes": [
                                    "$ENV://REDIS_NODE_0",
                                    "$ENV://REDIS_NODE_1"
                                ],
                                "redis_cluster_name": "redis-cluster-1",
                                "window_type": "sliding",
                                "sync_interval": 0.2
                            }
                        },
                        "upstream_id": "localhost_1980"
                    }]],
                },
                {
                    uri = "/apisix/admin/routes/hello2",
                    body = [[{
                        "uri": "/hello2",
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "policy": "redis-sentinel",
                                "redis_sentinels": [
                                     {"host": "127.0.0.1", "port": 26379}
                                 ],
                                 "redis_master_name": "mymaster",
                                 "redis_role": "master",
                                 "window_type": "sliding",
                                 "sync_interval": 0.2,
                                 "redis_database": 1
                            }
                        },
                        "upstream_id": "localhost_1980"
                    }]],
                },
            }
            local code, body
            for _, api in ipairs(apis) do
                code, body = t(api.uri, ngx.HTTP_PUT, api.body)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: sanity - delayed sync to redis
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]
--- wait: 1
--- grep_error_log eval
qr{delayed sync to redis}
--- grep_error_log_out eval
qr/(delayed sync to redis\n){3}/



=== TEST 3: sanity - delayed sync to redis-cluster
--- pipelined_requests eval
["GET /hello1", "GET /hello1", "GET /hello1"]
--- error_code eval
[200, 200, 503]
--- wait: 1
--- grep_error_log eval
qr{delayed sync to redis-cluster}
--- grep_error_log_out eval
qr/(delayed sync to redis-cluster\n){3}/



=== TEST 4: sanity - delayed sync to redis-sentinel
--- pipelined_requests eval
["GET /hello2", "GET /hello2", "GET /hello2"]
--- error_code eval
[200, 200, 503]
--- wait: 1
--- grep_error_log eval
qr{delayed sync to redis-sentinel}
--- grep_error_log_out eval
qr/(delayed sync to redis-sentinel\n){3}/
