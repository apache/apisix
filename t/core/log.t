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

repeat_each(2);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: error log
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            ngx.say("done")
        }
    }
--- log_level: error
--- request
GET /t
--- error_log
error log
--- no_error_log
warn log
notice log
info log



=== TEST 2: warn log
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            core.log.debug("debug log")
            ngx.say("done")
        }
    }
--- log_level: warn
--- request
GET /t
--- error_log
error log
warn log
--- no_error_log
notice log
info log
debug log



=== TEST 3: notice log
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            core.log.debug("debug log")
            ngx.say("done")
        }
    }
--- log_level: notice
--- request
GET /t
--- error_log
error log
warn log
notice log
--- no_error_log
info log
debug log



=== TEST 4: info log
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            core.log.debug("debug log")
            ngx.say("done")
        }
    }
--- log_level: info
--- request
GET /t
--- error_log
error log
warn log
notice log
info log
--- no_error_log
debug log



=== TEST 5: debug log
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            core.log.debug("debug log")
            ngx.say("done")
        }
    }
--- log_level: debug
--- request
GET /t
--- error_log
error log
warn log
notice log
info log
debug log



=== TEST 6: print error log with prefix
--- config
    location /t {
        content_by_lua_block {
            local log_prefix = require("apisix.core").log.new("prefix: ")
            log_prefix.error("error log")
            log_prefix.warn("warn log")
            log_prefix.notice("notice log")
            log_prefix.info("info log")
            ngx.say("done")
        }
    }
--- log_level: error
--- request
GET /t
--- error_log eval
qr/[error].+prefix: error log/
--- no_error_log
[qr/[warn].+warn log/, qr/[notice].+notice log/, qr/[info].+info log/]



=== TEST 7: print both prefixed error logs and normal logs
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local log_prefix = core.log.new("prefix: ")
            core.log.error("raw error log")
            core.log.warn("raw warn log")
            core.log.notice("raw notice log")
            core.log.info("raw info log")

            log_prefix.error("error log")
            log_prefix.warn("warn log")
            log_prefix.notice("notice log")
            log_prefix.info("info log")
            ngx.say("done")
        }
    }
--- log_level: error
--- request
GET /t
--- error_log eval
[qr/[error].+raw error log/, qr/[error].+prefix: error log/]
--- no_error_log
[qr/[warn].+warn log/, qr/[notice].+notice log/, qr/[info].+info log/]
