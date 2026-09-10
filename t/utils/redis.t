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

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: TLS SNI is redis_server_name or redis_host when redis_ssl is enabled
--- config
    location /t {
        content_by_lua_block {
            local last_opts
            local orig_redis = package.loaded["resty.redis"]
            package.loaded["resty.redis"] = {
                new = function()
                    return {
                        set_timeouts = function() end,
                        connect = function(_, host, port, opts)
                            last_opts = opts
                            return true
                        end,
                        get_reused_times = function()
                            return 1
                        end,
                    }
                end,
            }

            local function reload(name)
                package.loaded[name] = nil
                return require(name)
            end

            local cases = {
                {
                    conf = {redis_host = "127.0.0.1"},
                    expect = "nil",
                },
                {
                    conf = {redis_host = "redis.example.com", redis_ssl = true},
                    expect = "redis.example.com",
                },
                {
                    conf = {
                        redis_host = "10.0.0.1",
                        redis_ssl = true,
                        redis_server_name = "redis.example.com",
                    },
                    expect = "redis.example.com",
                },
                {
                    conf = {
                        redis_host = "redis.example.com",
                        redis_ssl = false,
                        redis_server_name = "ignored.example.com",
                    },
                    expect = "nil",
                },
            }

            local function run(label, connect)
                for _, case in ipairs(cases) do
                    last_opts = nil
                    connect(case.conf)
                    local got = last_opts and last_opts.server_name or "nil"
                    if got ~= case.expect then
                        ngx.say(label, " want ", case.expect, " got ", got)
                        return false
                    end
                    ngx.say(label, ": ", got)
                end
                return true
            end

            local redis = reload("apisix.utils.redis")
            if not run("utils", function(conf) redis.new(conf) end) then
                return
            end

            local util = reload("apisix.plugins.limit-count.util")
            run("util", function(conf) util.redis_cli(conf) end)

            package.loaded["resty.redis"] = orig_redis
            package.loaded["apisix.utils.redis"] = nil
            package.loaded["apisix.plugins.limit-count.util"] = nil
        }
    }
--- response_body
utils: nil
utils: redis.example.com
utils: redis.example.com
utils: nil
util: nil
util: redis.example.com
util: redis.example.com
util: nil
