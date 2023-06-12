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
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
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
                allow_degradation = false,
                rejected_code = 503,
                redis_timeout = 1000,
                key_type = "var",
                time_window = 60,
                show_limit_quota_header = true,
                count = 3,
                redis_host = "127.0.0.1",
                redis_port = 6379,
                redis_database = 0,
                policy = "redis",
                key = "remote_addr"
            }

            local lim_count_redis = require("apisix.plugins.limit-count.limit-count-redis")
            local lim = lim_count_redis.new("limit-count", 3, 60, conf)
            local uri = ngx.var.uri
            local _, remaining, _ = lim:incoming(uri, 2)

            ngx.say("remaining: ", remaining)
        }
    }
--- response_body
remaining: 1
