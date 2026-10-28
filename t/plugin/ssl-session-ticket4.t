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

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    # the same node id in every test, as a restarted node keeps it
    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<_EOC_);
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - 9100
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
        # the rounds are driven by the tests, with their own clock and policy
        $block->set_value("extra_yaml_config", <<_EOC_);
plugins:
  - example-plugin
stream_plugins:
  - ip-restriction
_EOC_
    }
});

run_tests;

__DATA__

=== TEST 1: the default local policy: disabled, generated, 1h and 19 keys
--- config
    location /t {
        content_by_lua_block {
            local record = require("apisix.plugins.ssl-session-ticket.record")
            local policy = record.policy()
            ngx.say(require("toolkit.json").encode(policy))
        }
    }
--- response_body
{"enabled":false,"generated":{"max_keys":19,"rotation_interval":3600},"key_source":"generated"}



=== TEST 2: the first key, then one more each rotation interval, 19 at most
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local gen = require("apisix.plugins.ssl-session-ticket.generator")
            local p = h.policy()
            local t0 = 1800000000
            h.delete_record()

            ngx.say((gen.round(p, t0)))
            local rec = h.parsed()
            ngx.say(#rec.keys, " ", rec.source, " ", rec.disabled, " ",
                    rec.origin.generated_at == t0)
            local first = rec.keys[1]

            ngx.say((gen.round(p, t0 + 3599)))

            local prev = first
            local counts = {}
            for i = 1, 20 do
                local res = gen.round(p, t0 + 3600 * i)
                rec = h.parsed()
                -- the new key issues, the previous one moves to the second place
                if res ~= "rotated" or rec.keys[2] ~= prev or rec.keys[1] == prev
                   or rec.origin.generated_at ~= t0 + 3600 * i then
                    ngx.say("unexpected rotation ", i)
                end
                prev = rec.keys[1]
                table.insert(counts, #rec.keys)

                local has_first = false
                for _, k in ipairs(rec.keys) do
                    has_first = has_first or k == first
                end
                if i == 18 or i == 19 then
                    -- the first key decrypts for 18 rotation intervals after it
                    -- stopped issuing, then it is gone
                    ngx.say("after ", i, "h the first key is kept: ", has_first)
                end
            end
            ngx.say(table.concat(counts, ","))
        }
    }
--- response_body
initialized
1 generated false true
idle
after 18h the first key is kept: true
after 19h the first key is kept: false
2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,19,19



=== TEST 3: a restart does not restart the period
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local gen = require("apisix.plugins.ssl-session-ticket.generator")
            local p = h.policy()
            local rec, rev = h.parsed()
            local last = rec.origin.generated_at
            ngx.say((gen.round(p, last + 3599)))
            local _, rev2 = h.parsed()
            ngx.say("unchanged: ", rev2 == rev)
            ngx.say((gen.round(p, last + 3600)))
        }
    }
--- response_body
idle
unchanged: true
rotated



=== TEST 4: after a long pause, one rotation only
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local gen = require("apisix.plugins.ssl-session-ticket.generator")
            local p = h.policy()
            local rec = h.parsed()
            local last = rec.origin.generated_at
            local second = rec.keys[1]

            local now = last + 10 * 3600
            ngx.say((gen.round(p, now)))
            rec = h.parsed()
            ngx.say(#rec.keys, " ", rec.keys[2] == second, " ", rec.origin.generated_at == now)
            ngx.say((gen.round(p, now)))
            ngx.say((gen.round(p, now + 3599)))
        }
    }
--- response_body
rotated
19 true true
idle
idle



=== TEST 5: fewer keys when max_keys is lowered, at once
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local gen = require("apisix.plugins.ssl-session-ticket.generator")
            local rec = h.parsed()
            local last = rec.origin.generated_at
            local newest = {rec.keys[1], rec.keys[2], rec.keys[3]}

            local p = h.policy({generated = {max_keys = 3}})
            ngx.say((gen.round(p, last + 1)))
            rec = h.parsed()
            ngx.say(#rec.keys, " ", rec.keys[1] == newest[1] and rec.keys[2] == newest[2]
                                     and rec.keys[3] == newest[3],
                    " ", rec.origin.generated_at == last)
            ngx.say((gen.round(p, last + 2)))
            ngx.say((gen.round(p, last + 3600)))
            rec = h.parsed()
            ngx.say(#rec.keys)
        }
    }
--- response_body
truncated
3 true true
idle
rotated
3



=== TEST 6: when two nodes are due at the same time, only one commits
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local gen = require("apisix.plugins.ssl-session-ticket.generator")
            local p = h.policy({generated = {max_keys = 5}})

            for trial = 1, 5 do
                local rec, rev = h.parsed()
                local due = rec.origin.generated_at + 3600
                local function node()
                    return (gen.round(p, due))
                end
                local t1 = ngx.thread.spawn(node)
                local t2 = ngx.thread.spawn(node)
                local _, r1 = ngx.thread.wait(t1)
                local _, r2 = ngx.thread.wait(t2)
                local after, rev2 = h.parsed()
                local outcomes = {r1, r2}
                table.sort(outcomes)
                -- exactly one new key, at the head of the previous set
                local one_new = after.keys[2] == rec.keys[1] and after.keys[1] ~= rec.keys[1]
                                and after.origin.generated_at == due
                ngx.say(trial, ": ", table.concat(outcomes, " "), " ", one_new)
            end
        }
    }
--- response_body
1: lost rotated true
2: lost rotated true
3: lost rotated true
4: lost rotated true
5: lost rotated true



=== TEST 7: disabling, enabling and switching the source write once each
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local gen = require("apisix.plugins.ssl-session-ticket.generator")
            local core = require("apisix.core")
            local record = require("apisix.plugins.ssl-session-ticket.record")
            local rec, rev = h.parsed()
            local now = rec.origin.generated_at + 1
            local keys = rec.keys

            local function step(p, label)
                local res = gen.round(p, now)
                local again = gen.round(p, now)
                local cur, rev2 = h.parsed()
                ngx.say(label, ": ", res, " then ", again, ", ", rev2 > rev, " ",
                        cur.source, " ", cur.disabled, " ", #cur.keys)
                rev = rev2
                return cur
            end

            local cur = step(h.policy({enabled = false, generated = {max_keys = 5}}), "disable")
            ngx.say("keys kept: ", cur.keys[1] == keys[1])
            cur = step(h.policy({generated = {max_keys = 5}}), "enable")
            ngx.say("keys kept: ", cur.keys[1] == keys[1])
            step(h.policy({key_source = "external"}), "to external")

            -- external keys, as the Admin API would have stored them
            core.etcd.set(h.etcd_key, record.build(h.raws(1, 2), {
                source = "external", disabled = false}))
            local _, ext_rev = h.parsed()
            rev = ext_rev
            cur = step(h.policy(), "to generated")
            ngx.say("external keys reused: ", cur.keys[1] == h.key(1) or cur.keys[1] == h.key(2),
                    " ", cur.origin.generated_at == now)
        }
    }
--- response_body
disable: disabled then idle, true generated true 5
keys kept: true
enable: enabled then idle, true generated false 5
keys kept: true
to external: switched then idle, true external false 0
to generated: switched then idle, true generated false 1
external keys reused: false true



=== TEST 8: nothing is written when the round fails
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local gen = require("apisix.plugins.ssl-session-ticket.generator")
            local core = require("apisix.core")
            local resty_random = require("resty.random")
            local p = h.policy()
            local rec, rev = h.parsed()
            local due = rec.origin.generated_at + 3600

            local encrypt = core.data_encryption.aes_cbc_encrypt
            core.data_encryption.aes_cbc_encrypt = function() return nil, "boom" end
            ngx.say(gen.round(p, due))
            core.data_encryption.aes_cbc_encrypt = encrypt

            local bytes = resty_random.bytes
            resty_random.bytes = function() return nil end
            ngx.say(gen.round(p, due))
            resty_random.bytes = bytes

            local _, rev2 = h.parsed()
            ngx.say("unchanged: ", rev2 == rev)

            -- a record this node cannot read is never overwritten
            core.etcd.set(h.etcd_key, {id = "ssl-session-ticket", keys = h.b64s(3)})
            local _, rev3 = h.record()
            ngx.say(gen.round(p, due))
            local _, rev4 = h.record()
            ngx.say("unchanged: ", rev4 == rev3)
            h.delete_record()
        }
    }
--- response_body
nilfailed to encrypt the keys: boom
nilfailed to generate a key
unchanged: true
nilthe current record can not be used: missing origin
unchanged: true



=== TEST 9: different policies pause the nodes and the Admin API, until they agree
--- extra_yaml_config
plugins:
  - example-plugin
stream_plugins:
  - ip-restriction
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local gen = require("apisix.plugins.ssl-session-ticket.generator")
            local record = require("apisix.plugins.ssl-session-ticket.record")
            local core = require("apisix.core")
            local json = require("toolkit.json")
            local fp = record.policy_fingerprint(record.policy())

            -- another node executing the policy with another configuration
            core.etcd.set("/ssl_session_ticket/policy/other-node",
                          {fingerprint = "0123abcd"}, 30)

            ngx.say(gen.policy_conflict(fp))
            local code, body = h.put_keys(1)
            ngx.say(code, " ", body)

            gen.run(ngx.time())
            local _, status = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            local g = json.decode(status).generator
            ngx.say(g.executes, " ", g.state, " ", g.error)
            ngx.say(select(2, h.record()))

            -- the other node is configured the same way
            core.etcd.set("/ssl_session_ticket/policy/other-node", {fingerprint = fp}, 30)
            ngx.say(gen.policy_conflict(fp))
            code = h.put_keys(1)
            ngx.say(code)

            gen.run(ngx.time())
            _, status = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            g = json.decode(status).generator
            ngx.say(g.executes, " ", g.state, " ", g.error)
            core.etcd.delete("/ssl_session_ticket/policy/other-node")
        }
    }
--- response_body
truethe nodes executing the policy have 2 different plugin_attr.ssl-session-ticket configurations (1 of 1 other registered nodes differ from this one)
409 {"error_msg":"writes are paused: the nodes executing the policy have 2 different plugin_attr.ssl-session-ticket configurations (1 of 1 other registered nodes differ from this one)"}
false conflict the nodes executing the policy have 2 different plugin_attr.ssl-session-ticket configurations (1 of 1 other registered nodes dif
404
false
201
false idle nil
--- error_log
pause the TLS session ticket keys: the nodes executing the policy have 2 different
the TLS session ticket generator is back to idle



=== TEST 10: the privileged agent generates and the adapters publish
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: true
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            h.delete_record()
            local snap = h.wait_state(function(s)
                return s.state == "ready" and s.origin.source == "generated"
            end, 15)
            ngx.say(snap.state, " ", #snap.keys, " ", snap.origin.source)
            local st = h.wait_generator(function(s) return s.state == "ok" end)
            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            local g = json.decode(body).generator
            ngx.say(g.executes, " ", g.state, " ",
                    g.last_generated_at:match("^%d+%-%d+%-%d+T%d+:%d+:%d+Z$") ~= nil, " ",
                    g.error)
        }
    }
--- response_body
ready 1 generated
true ok true nil
--- timeout: 20



=== TEST 11: a data plane never generates
--- yaml_config
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: etcd
  etcd:
    host:
      - "http://127.0.0.1:2379"
    prefix: /apisix
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: true
--- config
    location /t {
        content_by_lua_block {
            local status = require("apisix.session_ticket.status")
            ngx.sleep(7)
            local _, body = status.get()
            ngx.say(body.generator, " ", require("apisix.session_ticket.state").get_status("generator"))
        }
    }
--- response_body
null nil
--- timeout: 15



=== TEST 12: neither does a standalone node
--- yaml_config
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
--- apisix_yaml
routes: []
#END
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(6)
            local _, body = require("apisix.session_ticket.status").get()
            ngx.say(body.generator, " ", require("apisix.session_ticket.state").get_status("generator"))
        }
    }
--- response_body
null nil
--- timeout: 15
