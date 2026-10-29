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

# the runtime takes over the session ticket keys of the business TLS listeners
my $takeover = 0;
if ($version =~ m/--prefix=(\S+)\/nginx/) {
    $takeover = -f "$1/lualib/resty/apisix/ssl_session_ticket.lua";
}

if (!$takeover) {
    plan(skip_all => "the runtime does not take over the session ticket keys");
} else {
    plan('no_plan');
}

# The keys 51 and 52 fail as if the crypto library failed, the first to
# encrypt a ticket and the other to decrypt one: a debug build of the runtime
# only, read by the master when it loads the configuration.
$ENV{APISIX_TEST_SSL_SESSION_TICKET_FAIL_ENCRYPT} = unpack("H*", "ticket-name-0051");
$ENV{APISIX_TEST_SSL_SESSION_TICKET_FAIL_DECRYPT} = unpack("H*", "ticket-name-0052");

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
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
_EOC_
    }

    # the HTTPS listener (port 1994) tells what the connection has
    my $config = $block->config // "";
    $block->set_value("config", $config . <<_EOC_);
    location = /reused {
        content_by_lua_block {
            require("lib.ssl_session_ticket").respond()
        }
    }
_EOC_

    # a Stream TLS listener of the business, as apisix/cli/ngx_tpl.lua renders
    # it, that tells what the connection has
    if (!defined $block->stream_server_config) {
        $block->set_value("stream_server_config", <<_EOC_);
    listen 2005 ssl;
    ssl_certificate             cert/apisix.crt;
    ssl_certificate_key         cert/apisix.key;
    ssl_session_tickets off;
    apisix_ssl_session_ticket_takeover on;

    ssl_client_hello_by_lua_block {
        apisix.ssl_client_hello_phase()
    }

    ssl_certificate_by_lua_block {
        apisix.ssl_phase()
    }

    content_by_lua_block {
        local sock = ngx.req.socket()
        sock:receive()
        require("lib.ssl_session_ticket").respond()
    }
_EOC_
    }
    $block->set_value("stream_conf_enable", 1);
});

run_tests;

__DATA__

=== TEST 1: the business TLS contexts of both subsystems apply the keys
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            ngx.say(h.set_ssl())
            ngx.say((h.put_keys(1, 2)))
            local st = h.wait_applied()
            ngx.say(st.status, " ", st.reason, " ", st.key_count, " ", st.effective_key_count,
                    " ", st.fully_applied)
            -- one process serves both subsystems
            ngx.say("workers: ", json.encode(st.workers))
            for _, name in ipairs({"http", "stream"}) do
                local sub = st.subsystems[name]
                ngx.say(name, ": ", sub.applicable, " ", sub.status, " ", sub.contexts, " ",
                        json.encode(sub.workers), " draining: ", sub.draining.total)
            end
            -- the HTTPS context of this worker
            for _, ctx in ipairs(require("resty.apisix.ssl_session_ticket").contexts()) do
                ngx.say("context ", ctx.id, ": registered=", ctx.registered,
                        " tickets=", ctx.tickets, " keys=", ctx.keys)
            end
        }
    }
--- response_body
201
201
ok nil 2 2 true
workers: {"applied":1,"failed":0,"pending":0,"total":1}
http: true ok 1 {"applied":1,"failed":0,"pending":0,"total":1} draining: 0
stream: true ok 1 {"applied":1,"failed":0,"pending":0,"total":1} draining: 0
context 1: registered=true tickets=true keys=2
--- timeout: 15



=== TEST 2: TLSv1.2 sessions resume with the shared keys, HTTPS and Stream
A ticket of the first key resumes as it is: the callback does not renew it.
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            h.wait_applied()
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                local r = assert(h.connect(l[2], {http = l[3]}))
                ngx.say(l[1], ": ", r.protocol, " reused=", r.reused, " tickets=", r.tickets,
                        " first key: ", r.ticket == h.name(1))
                local again = assert(h.connect(l[2], {http = l[3], session = r.session}))
                ngx.say(l[1], ": resumed=", again.reused,
                        " same ticket: ", again.ticket_bytes == r.ticket_bytes)
            end
        }
    }
--- response_body
https: TLSv1.2 reused=false tickets=on first key: true
https: resumed=true same ticket: true
stream: TLSv1.2 reused=false tickets=on first key: true
stream: resumed=true same ticket: true
--- timeout: 15



=== TEST 3: TLSv1.3 sessions resume with the shared keys, HTTPS and Stream
TLSv1.3 renews the ticket on every resumption, as nginx does.
--- config
    location /t {
        lua_ssl_protocols TLSv1.3;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            h.wait_applied()
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                local r = assert(h.connect(l[2], {http = l[3]}))
                ngx.say(l[1], ": ", r.protocol, " reused=", r.reused, " tickets=", r.tickets,
                        " first key: ", r.ticket == h.name(1))
                local again = assert(h.connect(l[2], {http = l[3], session = r.session}))
                ngx.say(l[1], ": resumed=", again.reused, " renewed: ",
                        again.ticket == h.name(1) and again.ticket_bytes ~= r.ticket_bytes)
            end
        }
    }
--- response_body
https: TLSv1.3 reused=false tickets=on first key: true
https: resumed=true renewed: true
stream: TLSv1.3 reused=false tickets=on first key: true
stream: resumed=true renewed: true
--- timeout: 15



=== TEST 4: reordered, the new first key issues and the others decrypt; removed, no more
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            h.wait_applied()
            local first = {}
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                first[l[1]] = assert(h.connect(l[2], {http = l[3]}))
            end

            ngx.say((h.put_keys(2, 1)))
            h.wait_applied()
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                local r = assert(h.connect(l[2], {http = l[3]}))
                ngx.say(l[1], ": new tickets of the new first key: ", r.ticket == h.name(2))
                -- not the first key any more: renewed with the first one
                local old = assert(h.connect(l[2], {http = l[3], session = first[l[1]].session}))
                ngx.say(l[1], ": older key resumed=", old.reused,
                        " renewed: ", old.ticket == h.name(2))
            end

            ngx.say((h.put_keys(2)))
            h.wait_applied()
            -- the Stream listener has no session cache: only a ticket resumes
            local gone = assert(h.connect(2005, {session = first.stream.session}))
            ngx.say("stream: removed key resumed=", gone.reused,
                    " new ticket: ", gone.ticket == h.name(2))
        }
    }
--- response_body
200
https: new tickets of the new first key: true
https: older key resumed=true renewed: true
stream: new tickets of the new first key: true
stream: older key resumed=true renewed: true
200
stream: removed key resumed=false new ticket: true
--- timeout: 20



=== TEST 5: 0 -> n -> 0: without keys no stateless ticket, with keys again they are back
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            h.wait_applied()
            local before = assert(h.connect(2005))

            ngx.say((h.req(h.uri, ngx.HTTP_DELETE)))
            local st = h.wait_applied()
            ngx.say(st.status, " ", st.reason, " ", st.key_count, " ", st.effective_key_count,
                    " ", st.fully_applied)
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                local r = assert(h.connect(l[2], {http = l[3]}))
                ngx.say(l[1], ": tickets=", r.tickets, " ticket=", r.ticket)
            end
            local old = assert(h.connect(2005, {session = before.session}))
            ngx.say("stream: older ticket resumed=", old.reused)

            ngx.say((h.put_keys(3)))
            h.wait_applied()
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                local r = assert(h.connect(l[2], {http = l[3]}))
                ngx.say(l[1], ": tickets=", r.tickets, " key 3: ", r.ticket == h.name(3))
            end
        }
    }
--- response_body
200
off empty_keys 0 0 true
https: tickets=off ticket=nil
stream: tickets=off ticket=nil
stream: older ticket resumed=false
201
https: tickets=on key 3: true
stream: tickets=on key 3: true
--- timeout: 20



=== TEST 6: TLSv1.3 without keys still gets the stateful ticket of the session cache
--- config
    location /t {
        lua_ssl_protocols TLSv1.3;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            ngx.say((h.put_keys()))
            h.wait_applied()
            local r = assert(h.connect(1994, {http = true}))
            ngx.say("https: tickets=", r.tickets, " ticket=", r.ticket)
            local again = assert(h.connect(1994, {http = true, session = r.session}))
            ngx.say("https: resumed by the node: ", again.reused)
            ngx.say((h.put_keys(3)))
        }
    }
--- response_body
200
https: tickets=off ticket=stateful
https: resumed by the node: true
200
--- timeout: 15



=== TEST 7: the workers converge in the background, without any handshake
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local ticket = require("resty.apisix.ssl_session_ticket")
            local function show(st)
                local ctx = ticket.contexts()[1]
                ngx.say(st.status, " http=", st.subsystems.http.status,
                        " stream=", st.subsystems.stream.status,
                        " context: tickets=", ctx.tickets, " keys=", ctx.keys)
            end

            h.put_keys(4, 5, 6)
            show(h.wait_applied())
            h.put_keys()
            show(h.wait_applied())
            h.put_keys(4)
            show(h.wait_applied())
        }
    }
--- response_body
ok http=ok stream=ok context: tickets=true keys=3
off http=off stream=off context: tickets=false keys=0
ok http=ok stream=ok context: tickets=true keys=1
--- timeout: 20



=== TEST 8: the local switch off keeps every context off, whatever the keys
--- yaml_config
apisix:
  id: ssl-session-ticket-test
  node_listen: 1984
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - 9100
  ssl:
    ssl_session_tickets: false
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
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local st = h.wait_applied()
            ngx.say(st.status, " ", st.reason, " enabled=", st.enabled, " ", st.key_count, " ",
                    st.effective_key_count, " ", st.subsystems.http.reason, " ",
                    st.subsystems.stream.reason)
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                local r = assert(h.connect(l[2], {http = l[3]}))
                ngx.say(l[1], ": tickets=", r.tickets, " ticket=", r.ticket)
            end
        }
    }
--- response_body
off local_switch_off enabled=false 0 0 local_switch_off local_switch_off
https: tickets=off ticket=nil
stream: tickets=off ticket=nil
--- timeout: 15



=== TEST 9: HTTP applies, Stream fails: the node is degraded, the Stream context stays off
--- stream_extra_init_worker_by_lua
    -- every attempt of the Stream workers to install keys fails
    local ticket = require("resty.apisix.ssl_session_ticket")
    ticket.set_keys = function()
        return nil, "failed: injected"
    end
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            h.put_keys(7)
            h.wait_state(function(s) return s.keys[1] == h.key(7) end)
            local st = h.wait_status(function(st)
                return st.reason == "apply_failed" and st.subsystems.http.status == "ok"
            end)
            ngx.say(st.status, " ", st.reason, " ", st.key_count, " ", st.effective_key_count,
                    " ", st.fully_applied, " ", st.last_apply_error)
            ngx.say("workers: ", json.encode(st.workers))
            for _, name in ipairs({"http", "stream"}) do
                local sub = st.subsystems[name]
                ngx.say(name, ": ", sub.status, " ", sub.reason, " ", json.encode(sub.workers))
            end
            for _, l in ipairs({{"https", 1994, true}, {"stream", 2005}}) do
                local r = assert(h.connect(l[2], {http = l[3]}))
                ngx.say(l[1], ": tickets=", r.tickets, " key 7: ", r.ticket == h.name(7))
            end
        }
    }
--- response_body
degraded apply_failed 1 nil false context 1: failed: injected
workers: {"applied":0,"failed":1,"pending":0,"total":1}
http: ok nil {"applied":1,"failed":0,"pending":0,"total":1}
stream: degraded apply_failed {"applied":0,"failed":1,"pending":0,"total":1}
https: tickets=on key 7: true
stream: tickets=off key 7: false
--- error_log
failed to apply the TLS session ticket keys: context 1: failed: injected
--- timeout: 15



=== TEST 10: a handshake that waits in the ClientHello follows a switch made meanwhile
The connection is created while the context issues tickets; the keys are
gone before its ClientHello is processed: it issues no ticket. Only the
handshakes apply the target here, the timer of the worker does not run.
--- extra_init_worker_by_lua
    local h = require("lib.ssl_session_ticket")
    require("apisix.timers").unregister_timer("ssl#session_ticket")
    local client_hello = apisix.ssl_client_hello_phase
    apisix.ssl_client_hello_phase = function()
        h.client_hello_hook()
        return client_hello()
    end
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            h.put_keys(8)
            h.wait_state(function(s) return #s.keys == 1 and s.keys[1] == h.key(8) end)
            local r = assert(h.connect(1994, {http = true}))
            ngx.say("before: tickets=", r.tickets, " key 8: ", r.ticket == h.name(8))

            h.hold(true)
            local th = ngx.thread.spawn(h.connect, 1994, {http = true})
            ngx.say("held: ", h.wait_held())
            h.put_keys()
            h.wait_state(function(s) return s.state == "empty" end)
            h.hold(false)

            local ok, res = ngx.thread.wait(th)
            ngx.say("after: ", ok, " tickets=", res.tickets, " ticket=", res.ticket)
        }
    }
--- response_body
before: tickets=on key 8: true
held: true
after: true tickets=off ticket=nil
--- timeout: 15



=== TEST 11: a key that fails to encrypt or to decrypt fails the handshake, not the others
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            -- the first key encrypts
            h.put_keys(51)
            h.wait_applied()
            ngx.say("encrypt: ", select(2, h.connect(2005)))

            -- a ticket of the key 52, decrypted once 52 is no longer the first
            h.put_keys(52)
            h.wait_applied()
            local r = assert(h.connect(2005))
            h.put_keys(1, 52)
            h.wait_applied()
            ngx.say("decrypt: ", select(2, h.connect(2005, {session = r.session})))

            -- the other keys work
            local ok = assert(h.connect(2005))
            ngx.say("key 1: ", ok.ticket == h.name(1))
        }
    }
--- response_body_like
encrypt: handshake: .*
decrypt: handshake: .*
key 1: true
--- error_log
apisix ssl ticket encrypt with key "7469636b65742d6e616d652d30303531" failed for the test
apisix ssl ticket decrypt with key "7469636b65742d6e616d652d30303532" failed for the test
--- no_error_log
lua entry thread aborted
failed to apply the TLS session ticket keys
--- timeout: 20



=== TEST 12: draining and lagging workers, as the records of the workers tell
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local json = require("toolkit.json")
            local function show(st)
                local http = st.subsystems.http
                ngx.say(st.status, " ", st.reason, " ", st.effective_key_count, " ",
                        st.fully_applied, " workers=", json.encode(st.workers),
                        " http=", json.encode(http.workers),
                        " draining=", json.encode(http.draining))
            end

            h.put_keys(9)
            show(h.wait_applied())
            local generation = state.process_generation()

            -- a worker of the previous configuration generation that still
            -- runs and has not applied the target
            local old = {subsystem = "http", slot = 0, pid = 4242,
                         generation = generation - 1}
            state.put_worker_record(old, {applied_version = "previous", applied_gate = "ready",
                                          contexts = {{id = 1, ok = true}}})
            show(h.wait_status(function() return true end))

            -- it shuts down: its contexts are off for good
            state.put_worker_record(old, {applied_version = "previous", applied_gate = "ready",
                                          contexts = {{id = 1, ok = true}}, exiting = true})
            show(h.wait_status(function() return true end))
            state.delete_worker_record(old)

            -- a worker of the current generation that failed to install them
            local cur = {subsystem = "http", slot = 1, pid = 4343, generation = generation}
            state.put_worker_record(cur, {contexts = {{id = 1, ok = false,
                                                       error = "invalid_keys: oops"}}})
            show(h.wait_status(function() return true end))
            state.delete_worker_record(cur)
            show(h.wait_status(function() return true end))
        }
    }
--- response_body
ok nil 1 true workers={"applied":1,"failed":0,"pending":0,"total":1} http={"applied":1,"failed":0,"pending":0,"total":1} draining={"applied":0,"failed":0,"pending":0,"total":0}
degraded worker_lag nil false workers={"applied":1,"failed":0,"pending":1,"total":2} http={"applied":1,"failed":0,"pending":0,"total":1} draining={"applied":0,"failed":0,"pending":1,"total":1}
ok nil 1 true workers={"applied":2,"failed":0,"pending":0,"total":2} http={"applied":1,"failed":0,"pending":0,"total":1} draining={"applied":1,"failed":0,"pending":0,"total":1}
degraded apply_failed nil false workers={"applied":1,"failed":1,"pending":0,"total":2} http={"applied":1,"failed":1,"pending":0,"total":2} draining={"applied":0,"failed":0,"pending":0,"total":0}
ok nil 1 true workers={"applied":1,"failed":0,"pending":0,"total":1} http={"applied":1,"failed":0,"pending":0,"total":1} draining={"applied":0,"failed":0,"pending":0,"total":0}
--- timeout: 15



=== TEST 13: the tests may keep the TLS listeners of the framework as they were
`--- legacy_ssl_session_tickets`: the HTTPS listener of t::APISIX is not
marked, it only resumes from its session cache.
--- legacy_ssl_session_tickets
--- config
    location /t {
        lua_ssl_protocols TLSv1.2;
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            h.put_keys(10)
            h.wait_state(function(s) return s.keys[1] == h.key(10) end)
            ngx.say("contexts: ", #require("resty.apisix.ssl_session_ticket").contexts())
            local r = assert(h.connect(1994, {http = true}))
            ngx.say("tickets=", r.tickets, " ticket=", r.ticket)
            local again = assert(h.connect(1994, {http = true, session = r.session}))
            ngx.say("resumed from the session cache: ", again.reused)
        }
    }
--- response_body
contexts: 0
tickets=not_marked ticket=nil
resumed from the session cache: true
--- timeout: 15
