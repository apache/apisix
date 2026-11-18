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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    my $config = <<_EOC_;
    location /t {
        content_by_lua_block {
            -- mock an apiserver which serves the Endpoints list in two pages,
            -- the status of the second page is taken from the request args
            local core = require("apisix.core")
            local http = require("resty.http")
            local second_page_status = tonumber(ngx.var.arg_second_page_status)
            local http_new_orig = http.new
            http.new = function()
                local mock = {}
                mock.connect = function() return true end
                mock.set_timeouts = function() end
                mock.request = function(_, params)
                    if core.string.find(params.query, "watch=true") then
                        return nil, "watch is not mocked"
                    end

                    local status = 200
                    local data = {
                        kind = "EndpointsList",
                        metadata = {resourceVersion = "1", continue = "page2"},
                        items = {{metadata = {name = "svc-a"}}},
                    }
                    if core.string.find(params.query, "continue=page2") then
                        status = second_page_status
                        data.metadata = {resourceVersion = "2"}
                        data.items = {{metadata = {name = "svc-b"}}}
                    end

                    local body = core.json.encode(data)
                    return {
                        status = status,
                        reason = status == 200 and "OK" or "Internal Server Error",
                        read_body = function() return body end,
                    }
                end
                return mock
            end

            local factory = require("apisix.discovery.kubernetes.informer_factory")
            local informer = factory.new(nil, "v1", "Endpoints", "endpoints", nil)
            local added = {}
            informer.on_added = function(_, item)
                core.table.insert(added, item.metadata.name)
            end
            informer.post_list = function()
                ngx.say("post_list called")
            end

            informer:list_watch({schema = "http", host = "127.0.0.1", port = 6443, token = ""})
            http.new = http_new_orig

            ngx.say("added: ", table.concat(added, ","))
            ngx.say("fetch_state: ", informer.fetch_state)
        }
    }
_EOC_

    $block->set_value("config", $config);
});

run_tests;

__DATA__

=== TEST 1: all pages are listed before post_list
--- request
GET /t?second_page_status=200
--- response_body
post_list called
added: svc-a,svc-b
fetch_state: watch failed
--- error_log
watch failed, kind: Endpoints, reason: RequestError



=== TEST 2: a failed later page fails the list and skips post_list
--- request
GET /t?second_page_status=500
--- response_body
added: svc-a
fetch_state: list failed
--- error_log
list failed, kind: Endpoints, reason: Internal Server Error
