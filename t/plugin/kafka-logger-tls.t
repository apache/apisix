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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_init_by_lua = <<_EOC_;
    local bp_manager = require("apisix.utils.batch-processor-manager")
    local core = require("apisix.core")
    local function log_send_data(entry)
        local data = type(entry) == "table" and core.json.encode(entry) or entry
        core.log.info("send data to kafka: ", data)
    end
    local old_add = bp_manager.add_entry
    bp_manager.add_entry = function(self, conf, entry, max_pending_entries)
        local ok = old_add(self, conf, entry, max_pending_entries)
        if ok then
            log_send_data(entry)
        end
        return ok
    end
    local old_new = bp_manager.add_entry_to_new_processor
    bp_manager.add_entry_to_new_processor = function(self, conf, entry, ctx, func, max_pending_entries)
        local ok = old_new(self, conf, entry, ctx, func, max_pending_entries)
        if ok then
            log_send_data(entry)
        end
        return ok
    end
_EOC_

    if (!defined $block->extra_init_by_lua) {
        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }
});

run_tests;

__DATA__

=== TEST 1: tls schema validation - valid tls config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                brokers = {{host = "127.0.0.1", port = 9093}},
                kafka_topic = "test",
                tls = { verify = false }
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: tls schema validation - without tls (backward compatibility)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                brokers = {{host = "127.0.0.1", port = 9092}},
                kafka_topic = "test"
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 3: tls schema validation - wrong type for verify
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                brokers = {{host = "127.0.0.1", port = 9093}},
                kafka_topic = "test",
                tls = { verify = "abc" }
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "tls" validation failed: property "verify" validation failed: wrong type: expected boolean, got string
done
