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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

# Whether the runtime takes over the session ticket keys of the business TLS
# listeners. Without it, nothing applies the keys and the status says so:
# `--- response_body_takeover` is what the status says with it.
my $takeover = 0;
if ($version =~ m/--prefix=(\S+)\/nginx/) {
    $takeover = -f "$1/lualib/resty/apisix/ssl_session_ticket.lua";
}

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ($takeover && defined $block->response_body_takeover) {
        $block->set_value("response_body", $block->response_body_takeover);
    }

    # the same node id in every test, as a restarted node keeps it
    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<_EOC_);
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  enable_resolv_search_opt: false
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
_EOC_
    }

    if (!defined $block->extra_yaml_config) {
        $block->set_value("extra_yaml_config", <<_EOC_);
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
_EOC_
    }
});

run_tests;

__DATA__

=== TEST 1: without a record there is no source and no source version
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            h.wait_state(function(s) return s.state ~= "pending" end)
            h.wait_status()
            local code, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(code, " ", body.status, " ", body.reason, " ", body.key_count, " ",
                    body.fully_applied, " ", body.source, " ", body.source_version)
        }
    }
--- response_body
200 degraded module_not_active 0 false nil nil
--- response_body_takeover
200 off empty_keys 0 true nil nil
--- timeout: 15



=== TEST 2: the fields of a published target
--- yaml_config
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  ssl:
    ssl_session_tickets: true
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
--- extra_yaml_config
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            h.put_keys(1, 2, 3)
            local _, rev = h.record()
            h.wait_state(function(s) return s.origin and s.origin.revision == rev end)
            h.wait_status()

            local code, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            ngx.say("leak: ", h.leaks(body, 1, 2, 3))
            body = json.decode(body)
            ngx.say(code, " ", body.status, " ", body.reason, " ", body.enabled)
            ngx.say("key_count: ", body.key_count, " effective: ", body.effective_key_count,
                    " fully_applied: ", body.fully_applied)
            ngx.say("source: ", body.source, " ", body.source_version == tostring(rev))
            ngx.say("version: ", body.version:match("^%x+:%d+$") ~= nil)
            ngx.say("updated_at: ", body.updated_at:match("^%d+%-%d+%-%d+T%d+:%d+:%d+Z$") ~= nil,
                    " ", body.updated_at_sec_ago >= 0)
            ngx.say("workers: ", json.encode(body.workers))
            for _, name in ipairs({"http", "stream"}) do
                local sub = body.subsystems[name]
                ngx.say(name, ": ", sub.applicable, " ", sub.status, " ", sub.reason, " ",
                        sub.contexts, " ", json.encode(sub.workers))
            end
            ngx.say("warnings: ", json.encode(body.warnings))
            ngx.say("generator: ", body.generator.executes, " ", body.generator.state, " ",
                    body.generator.last_generated_at, " ", body.generator.error)
        }
    }
--- response_body
leak: false
200 degraded module_not_active true
key_count: 3 effective: nil fully_applied: false
source: external true
version: true
updated_at: true true
workers: {"applied":0,"failed":0,"pending":0,"total":0}
http: false degraded module_not_active 0 {"applied":0,"failed":0,"pending":0,"total":0}
stream: false off nil 0 {"applied":0,"failed":0,"pending":0,"total":0}
warnings: ["default_keyring"]
generator: false idle nil nil
--- response_body_takeover
leak: false
200 ok nil true
key_count: 3 effective: 3 fully_applied: true
source: external true
version: true
updated_at: true true
workers: {"applied":1,"failed":0,"pending":0,"total":1}
http: true ok nil 1 {"applied":1,"failed":0,"pending":0,"total":1}
stream: false off nil 0 {"applied":0,"failed":0,"pending":0,"total":0}
warnings: ["default_keyring"]
generator: false idle nil nil
--- timeout: 15



=== TEST 3: the target count is 0 when the local switch is off
--- yaml_config
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  ssl:
    ssl_session_tickets: false
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            local _, rev = h.record()
            h.wait_state(function(s) return s.origin and s.origin.revision == rev end)
            h.wait_status()
            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(body.enabled, " ", body.key_count, " ", body.status, " ", body.reason, " ",
                    body.effective_key_count)
        }
    }
--- response_body
false 0 degraded module_not_active nil
--- response_body_takeover
false 0 off local_switch_off 0
--- timeout: 15



=== TEST 4: reading changes nothing
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local _, rev = h.record()
            local before = h.wait_state(function(s)
                return s.origin and s.origin.revision == rev
            end)
            local dict = ngx.shared["tls-session-ticket"]
            local ctl = dict:get("ctl")
            for _ = 1, 20 do
                h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            end
            local after = state.read()
            ngx.say(dict:get("ctl") == ctl, " ", after.version == before.version,
                    " ", after.updated_at == before.updated_at)
        }
    }
--- response_body
true true true
--- timeout: 15



=== TEST 5: only GET
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            for _, method in ipairs({ngx.HTTP_POST, ngx.HTTP_PUT, ngx.HTTP_DELETE}) do
                ngx.say((h.req("/v1/tls_session_ticket", method)))
            end
        }
    }
--- response_body
404
404
404



=== TEST 6: the endpoint stays when the plugin is not enabled
--- extra_yaml_config
plugins:
  - example-plugin
stream_plugins:
  - ip-restriction
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            ngx.sleep(1.5)
            h.wait_status()
            local code, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(code, " ", body.status, " ", body.reason, " ", body.key_count, " ",
                    body.source)
        }
    }
--- response_body
200 degraded module_not_active 0 nil
--- response_body_takeover
200 off empty_keys 0 nil
--- timeout: 15



=== TEST 7: a subsystem that is not enabled is off and not applicable
--- yaml_config
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  proxy_mode: http
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            local _, rev = h.record()
            h.wait_state(function(s) return s.origin and s.origin.revision == rev end)
            local body = h.wait_status()
            for _, name in ipairs({"http", "stream"}) do
                local sub = body.subsystems[name]
                ngx.say(name, ": ", sub.applicable, " ", sub.status, " ", sub.reason)
            end
        }
    }
--- response_body
http: false degraded module_not_active
stream: false off nil
--- response_body_takeover
http: true ok nil
stream: false off nil
--- timeout: 15



=== TEST 8: the plugin metadata dumps are redacted
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            local _, rev = h.record()
            h.wait_state(function(s) return s.origin and s.origin.revision == rev end)
            -- the dumps read the watched records, wait for this worker to have it
            ngx.sleep(1)

            local code, body = h.req("/v1/plugin_metadata/ssl-session-ticket", ngx.HTTP_GET)
            ngx.say(code, " leak: ", h.leaks(body, 1, 2, 3))
            ngx.say(json.encode(json.decode(body).keys))

            local value = h.record()
            ngx.say("ciphertext: ", body:find(value.keys[1], 1, true) ~= nil)

            code, body = h.req("/v1/plugin_metadatas", ngx.HTTP_GET)
            ngx.say(code, " leak: ", h.leaks(body, 1, 2, 3))
            for _, item in ipairs(json.decode(body)) do
                if item.id == "ssl-session-ticket" then
                    ngx.say(json.encode(item.keys))
                end
            end
            ngx.say("ciphertext: ", body:find(value.keys[1], 1, true) ~= nil)
        }
    }
--- response_body
200 leak: false
["<redacted>","<redacted>","<redacted>"]
ciphertext: false
200 leak: false
["<redacted>","<redacted>","<redacted>"]
ciphertext: false
--- timeout: 15
