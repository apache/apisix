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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: semantic math helpers (normalize / dot / cosine / max)
--- config
    location /t {
        content_by_lua_block {
            local s = require("apisix.plugins.ai-proxy.semantic")
            local function approx(a, b) return math.abs(a - b) < 1e-9 end

            -- normalize
            local n = s.normalize({3, 4})
            assert(approx(n[1], 0.6) and approx(n[2], 0.8), "normalize unit vector")
            local z = s.normalize({0, 0})
            assert(approx(z[1], 0) and approx(z[2], 0), "normalize zero vector")

            -- cosine
            assert(approx(s.cosine({1, 0}, {1, 0}), 1.0), "cosine identical")
            assert(approx(s.cosine({1, 0}, {0, 1}), 0.0), "cosine orthogonal")
            assert(approx(s.cosine({1, 1}, {2, 2}), 1.0), "cosine same direction")
            assert(approx(s.cosine({1, 0}, {-1, 0}), -1.0), "cosine opposite")

            -- dot on normalized == cosine
            local a = s.normalize({1, 2, 3})
            assert(approx(s.dot(a, a), 1.0), "dot of normalized identical")

            -- max: an instance scores by its best-matching example, so one
            -- dead-on example is not diluted by the instance's broader ones
            assert(approx(s.max({0.7, 0.85}), 0.85), "max picks the best")
            assert(approx(s.max({1.0, 0.5, 0.4}), 1.0), "max is not diluted")
            assert(approx(s.max({0.5}), 0.5), "max of a single score")
            assert(s.max({}) == nil, "max of empty is nil")

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
