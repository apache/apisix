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
    $ENV{TEST_ENABLE_CONTROL_API_V1} = "0";
}

use t::APISIX 'no_plan';

log_level("info");
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

=== TEST 1: valid config - exact layer only
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "exact" },
                exact = { ttl = 600 },
                redis = {
                    host = "127.0.0.1",
                    port = 6379,
                }
            })

            if not ok then
                ngx.say("failed")
            else
                ngx.say("passed")
            end 
        }
    }
--- response_body
passed



=== TEST 2: valid config - both layers with semantic embedding
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "exact", "semantic" },
                exact = { ttl = 3600 },
                semantic = {
                    similarity_threshold = 0.95,
                    ttl = 86400,
                    embedding = {
                        provider = "openai",
                        endpoint = "https://api.openai.com/v1/embeddings",
                        api_key = "sk-test",
                    },
                },
                redis = { host = "127.0.0.1", port = 6379 },
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 3: semantic without embedding config - should fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "semantic" },
            })
            if not ok then
                ngx.say("failed: ", err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
failed: semantic layer requires semantic.embedding to be configured



=== TEST 4: invalid layer value - should fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "invalid_layer" },
            })
            if not ok then
                ngx.say("failed")
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
failed



=== TEST 5: unsupported embedding provider - should fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "semantic" },
                semantic = {
                    embedding = {
                        provider = "some-unknown-provider",
                        endpoint = "https://example.com/embeddings",
                        api_key = "key",
                    },
                },
            })

            if not ok then
                ngx.say("failed")
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
failed



=== TEST 6: similarity_threshold out of range - should fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ai-cache")
            local ok, err = plugin.check_schema({
                layers = { "semantic" },
                semantic = {
                    similarity_threshold = 1.5,
                    embedding = {
                        provider = "openai",
                        endpoint = "https://api.openai.com/v1/embeddings",
                        api_key = "sk-test",
                    },
                },
            })

            if not ok then
                ngx.say("failed")
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
failed
