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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;
    my $test = $block->test;

    $block->set_value("config", <<_EOC_);
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local limiter = require("apisix.plugins.limit-conn.init")
            local counters = ngx.shared["plugin-limit-conn"]

            -- These are inputs to the real limiter. No limiter, shared
            -- dictionary, variable resolver, or clock is replaced.
            local function config(resource)
                return {
                    conn = 1,
                    burst = 0,
                    default_conn_delay = 0.01,
                    only_use_default_delay = true,
                    key = "http_subject",
                    key_type = "var",
                    policy = "local",
                    rejected_code = 503,
                    _meta = {parent = {resource_key = "/identity-test/" .. resource}},
                }
            end

            local function enter(conf, expected)
                local ctx = {var = ngx.var}
                local code = limiter.increase(conf, ctx)
                assert(code == expected, "unexpected admission: " .. tostring(code))
                return ctx
            end

            local function key(ctx, index)
                assert(ctx.limit_conn, "request must own a reservation")
                return ctx.limit_conn[(index or 1) * 4 - 2]
            end

            local function count(k, expected)
                local actual = counters:get(k)
                assert(actual == expected,
                       "unexpected counter: " .. tostring(actual) .. " != " .. expected)
            end

            local function leave(conf, ctx)
                limiter.decrease(conf, ctx)
                assert(ctx.limit_conn == nil, "reservation context was not released")
            end

            $test
            ngx.say("passed")
        }
    }
_EOC_
    $block->set_value("request", "GET /t");
    $block->set_value("more_headers", "Subject: tenant:{shared}:one\nOther: tenant:{shared}:one");
    $block->set_value("response_body", "passed\n");
    $block->set_value("no_error_log", "[error]\n[alert]");
});

run_tests();

__DATA__

=== TEST 1: non-identity settings keep the occupied counter
--- test
    local changes = {
        function(c) c._meta.priority = 1003 end,
        function(c) c.rejected_code = 429 end,
        function(c) c.rejected_msg = "try again later" end,
        function(c) c.default_conn_delay = 0.02 end,
        function(c) c.only_use_default_delay = false end,
        function(c) c.allow_degradation = true end,
        function(c) c.redis_timeout = 2500 end,
        function(c) c.redis_password = "rotated-test-credential" end,
        function(c) c.key_ttl = 10 end,
        function(c) c.key_type = nil end,
    }

    for i, change in ipairs(changes) do
        local old = config("settings-" .. i)
        local new = config("settings-" .. i)
        change(new)
        local occupied = enter(old)
        local original_key = key(occupied)
        count(original_key, 1)

        local rejected = enter(new, new.rejected_code)
        assert(rejected.limit_conn == nil, "rejected request reserved capacity")
        count(original_key, 1)
        leave(new, occupied)
        count(original_key, 0)

        local admitted = enter(new)
        assert(key(admitted) == original_key, "settings update changed the counter")
        count(original_key, 1)
        leave(new, admitted)
        count(original_key, 0)
    end



=== TEST 2: raising and lowering thresholds retains in-flight reservations
--- test
    local original = config("thresholds")
    local raised = config("thresholds")
    raised.conn = 2
    local first = enter(original)
    local original_key = key(first)
    local second = enter(raised)
    assert(key(second) == original_key, "raising the limit reset occupancy")
    count(original_key, 2)
    enter(raised, 503)

    local lowered = config("thresholds")
    enter(lowered, 503)
    leave(lowered, first)
    count(original_key, 1)
    enter(lowered, 503)
    leave(lowered, second)
    count(original_key, 0)

    local third = enter(lowered)
    assert(key(third) == original_key)
    leave(lowered, third)
    count(original_key, 0)



=== TEST 3: resources, subject definitions, and workflow actions are isolated
--- test
    local confs = {config("scope-a"), config("scope-b"), config("scope-a"),
                   config("scope-a"), config("scope-a"), config("scope-a")}
    confs[3].key = "http_other"
    confs[4].key_type = "var_combination"
    confs[4].key = "$http_subject"
    confs[5]._vid = 1
    confs[6]._vid = 2

    local seen, requests = {}, {}
    for i, conf in ipairs(confs) do
        requests[i] = enter(conf)
        local k = key(requests[i])
        assert(not seen[k], "independent policies shared a counter")
        seen[k] = true
        count(k, 1)
        enter(conf, 503)
    end
    for i, conf in ipairs(confs) do
        local k = key(requests[i])
        leave(conf, requests[i])
        count(k, 0)
    end



=== TEST 4: rule reordering preserves each expression's counter
--- test
    local original = config("reorder")
    original.rules = {
        {conn = 2, burst = 0, key = "$http_subject"},
        {conn = 2, burst = 0, key = "$http_other"},
    }
    local reordered = config("reorder")
    reordered.rules = {core.table.deepcopy(original.rules[2]),
                       core.table.deepcopy(original.rules[1])}

    local first = enter(original)
    local subject_key, other_key = key(first, 1), key(first, 2)
    assert(subject_key ~= other_key, "different dimensions with the same value collided")
    local second = enter(reordered)
    assert(key(second, 1) == other_key and key(second, 2) == subject_key,
           "reordering changed a rule's identity")
    count(subject_key, 2)
    count(other_key, 2)
    enter(reordered, 503)
    leave(reordered, first)
    count(subject_key, 1)
    count(other_key, 1)
    leave(reordered, second)
    count(subject_key, 0)
    count(other_key, 0)



=== TEST 5: duplicate expressions retain shared counters and sequential admission
--- test
    local conf = config("duplicates")
    conf.rules = {
        {conn = 2, burst = 0, key = "$http_subject"},
        {conn = 3, burst = 0, key = "$http_subject"},
    }
    local first = enter(conf)
    local k1, k2 = key(first, 1), key(first, 2)
    assert(k1 == k2, "duplicate expressions created separate counters")
    count(k1, 2)
    enter(conf, 503)
    count(k1, 2)
    leave(conf, first)
    count(k1, 0)



=== TEST 6: reordering duplicate expressions with a skipped rule retains occupancy
--- test
    local original = config("skipped")
    original.rules = {
        {conn = "$http_missing", burst = 0, key = "$http_subject"},
        {conn = 2, burst = 0, key = "$http_subject"},
    }
    local updated = config("skipped")
    updated.rules = {core.table.deepcopy(original.rules[2]),
                     core.table.deepcopy(original.rules[1])}

    local first = enter(original)
    assert(#first.limit_conn == 4, "invalid rule was not skipped")
    local original_key = key(first)
    local second = enter(updated)
    assert(#second.limit_conn == 4, "invalid rule was not skipped")
    assert(key(second) == original_key, "reordering duplicate expressions changed the counter")
    count(original_key, 2)
    enter(updated, 503)
    leave(updated, first)
    count(original_key, 1)
    leave(updated, second)
    count(original_key, 0)



=== TEST 7: request IDs and Redis hash-tag characters do not define buckets
--- test
    local conf = config("hash-tag")
    conf.key_type = "var_combination"
    conf.key = "${http_subject}"
    ngx.ctx.request_id = "first-request"
    local first = enter(conf)
    local k = key(first)
    assert(not k:find("[{}]"), "subject or expression injected a Redis hash tag")
    ngx.ctx.request_id = "second-request"
    enter(conf, 503)
    count(k, 1)
    leave(conf, first)
    count(k, 0)



=== TEST 8: a later rule rejecting releases only the earlier reservation
--- test
    local conf = config("partial-admission")
    conf.rules = {
        {conn = 2, burst = 0, key = "$http_subject"},
        {conn = 1, burst = 0, key = "$http_other"},
    }
    local first = enter(conf)
    local k1, k2 = key(first, 1), key(first, 2)
    local rejected = enter(conf, 503)
    assert(#rejected.limit_conn == 4, "rejected rule retained a reservation")
    assert(key(rejected) == k1)
    count(k1, 2)
    count(k2, 1)
    leave(conf, rejected)
    count(k1, 1)
    count(k2, 1)
    leave(conf, first)
    count(k1, 0)
    count(k2, 0)



=== TEST 9: an old request releases its original subject definition
--- test
    local original = config("changed-subject")
    local updated = config("changed-subject")
    updated.key = "http_other"
    local first = enter(original)
    local old_key = key(first)
    local second = enter(updated)
    local new_key = key(second)
    assert(old_key ~= new_key)
    leave(updated, first)
    count(old_key, 0)
    count(new_key, 1)
    enter(updated, 503)
    leave(updated, second)
    count(new_key, 0)
