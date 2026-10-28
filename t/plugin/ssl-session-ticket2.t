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
workers(2);

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->extra_yaml_config) {
        # only the tests drive the state
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

=== TEST 1: the main-level dict is shared: HTTP publishes, Stream reads, and the reverse
--- stream_conf_enable
--- stream_server_config
    # a tiny protocol to act on the state from the Stream subsystem
    content_by_lua_block {
        local h = require("lib.ssl_session_ticket")
        local state = require("apisix.session_ticket.state")
        local sock = ngx.req.socket()
        local line = sock:receive()
        local cmd, rev, n = line:match("^(%w+) ?(%d*) ?(%d*)$")
        if cmd == "publish" then
            local res, err = state.publish({state = "ready", record = true,
                                            source = "external", disabled = false,
                                            revision = tonumber(rev),
                                            keys = h.raws(tonumber(n))})
            ngx.say(res or err)
            return
        end
        local snap, err = state.read()
        if not snap then
            ngx.say(err)
            return
        end
        local keys = {}
        for i, k in ipairs(snap.keys) do
            keys[i] = ngx.encode_base64(k)
        end
        ngx.say(snap.version, " ", snap.state, " ", table.concat(keys, ","))
    }
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")

            local function stream(cmd)
                local sock = ngx.socket.tcp()
                assert(sock:connect("127.0.0.1", 1985))
                assert(sock:send(cmd .. "\n"))
                local data = sock:receive("*a")
                sock:close()
                return (data:gsub("\n$", ""))
            end

            ngx.say((state.publish({state = "ready", record = true, source = "external",
                                   revision = 10, keys = h.raws(1, 2)})))
            local snap = state.read()
            local http_view = snap.version .. " " .. snap.state .. " "
                              .. table.concat(h.b64s(1, 2), ",")
            ngx.say("stream reads it: ", stream("read") == http_view)

            ngx.say(stream("publish 11 3"))
            snap = state.read()
            ngx.say(snap.state, " ", snap.origin.revision, " ",
                    #snap.keys == 1 and snap.keys[1] == h.key(3))
            ngx.say("same version: ", stream("read"):match("^%S+") == snap.version)

            -- the same candidate from the other VM is a duplicate
            ngx.say(stream("publish 11 3"))
        }
    }
--- response_body
published
stream reads it: true
published
ready 11 true
same version: true
duplicate



=== TEST 2: repeated notifications publish once and never refresh updated_at
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local cand = {state = "ready", record = true, source = "external",
                          revision = 20, keys = h.raws(1)}
            ngx.say((state.publish(cand)))
            local snap = state.read()
            ngx.sleep(1.1)
            ngx.say((state.publish(cand)))
            ngx.say((state.publish(cand)))
            local again = state.read()
            ngx.say(again.version == snap.version, " ", again.updated_at == snap.updated_at)
        }
    }
--- response_body
published
duplicate
duplicate
true true



=== TEST 3: versions order the snapshots, not the clock
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local now = ngx.now
            local function publish(at, revision, n)
                ngx.now = function() return at end
                local res, err = state.publish({state = "ready", record = true,
                                                source = "external", revision = revision,
                                                keys = h.raws(n)})
                ngx.now = now
                local snap = state.read()
                local key = "?"
                for i = 1, 3 do
                    if snap.keys[1] == h.key(i) then
                        key = i
                    end
                end
                ngx.say(res or err, " seq=", snap.seq, " at=", snap.updated_at, " key=", key)
            end

            publish(1000, 10, 1)
            -- the same second
            publish(1000, 11, 2)
            -- the clock went back
            publish(900, 12, 3)
            -- an older event after a newer one
            publish(1100, 11, 2)
        }
    }
--- response_body
published seq=1 at=1000 key=1
published seq=2 at=1000 key=2
published seq=3 at=900 key=3
stale seq=3 at=900 key=3



=== TEST 4: out of order and after a deletion, an older event never comes back
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local function show(res, err)
                local snap = state.read()
                ngx.say(res or err, " ", snap.seq, " ", snap.state, " ", #snap.keys, " ",
                        snap.origin and snap.origin.revision or "no record")
            end

            show(state.publish({state = "ready", record = true, source = "external",
                                revision = 20, keys = h.raws(1)}))
            -- deleted at revision 30
            show(state.publish({state = "empty", record = false, revision = 30}))
            -- late events of the deleted record
            show(state.publish({state = "ready", record = true, source = "external",
                                revision = 20, keys = h.raws(1)}))
            show(state.publish({state = "ready", record = true, source = "external",
                                revision = 25, keys = h.raws(2)}))
            -- still no record, later: only the watermark moves
            show(state.publish({state = "empty", record = false, revision = 35}))
            show(state.publish({state = "ready", record = true, source = "external",
                                revision = 33, keys = h.raws(2)}))
            -- created again
            show(state.publish({state = "ready", record = true, source = "external",
                                revision = 40, keys = h.raws(3)}))
        }
    }
--- response_body
published 1 ready 1 20
published 2 empty 0 no record
stale 2 empty 0 no record
stale 2 empty 0 no record
watermark 2 empty 0 no record
stale 2 empty 0 no record
published 3 ready 1 40



=== TEST 5: when the snapshot cannot be stored, nothing of the old one is used and it shows
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local json = require("toolkit.json")
            local dict = ngx.shared["tls-session-ticket"]

            ngx.say((state.publish({state = "ready", record = true, source = "external",
                                   revision = 50, keys = h.raws(1)})))

            -- no memory left
            local n = 0
            while dict:safe_set("junk" .. n, string.rep("x", 4000)) do
                n = n + 1
            end

            local many = {}
            for i = 1, 200 do
                many[i] = i
            end
            local res, err = state.publish({state = "ready", record = true,
                                            source = "external", revision = 51,
                                            keys = h.raws(unpack(many))})
            ngx.say(res, " ", err)

            local snap = state.read()
            ngx.say(snap.gate, " ", snap.state, " ", #snap.keys, " ", snap.error)
            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(body.status, " ", body.reason, " ", body.key_count, " ",
                    body.last_apply_error)

            -- memory is back: the same revision is retried as a new version
            for i = 0, n - 1 do
                dict:delete("junk" .. i)
            end
            local failed_seq = snap.seq
            ngx.say((state.publish({state = "ready", record = true, source = "external",
                                   revision = 51, keys = h.raws(unpack(many))})))
            snap = state.read()
            ngx.say(snap.gate, " ", snap.state, " ", #snap.keys, " ",
                    snap.seq == failed_seq + 1)
        }
    }
--- response_body
published
nil failed to store the snapshot: no memory
unavailable unavailable 0 failed to store the snapshot
degraded invalid_state 0 failed to store the snapshot
published
ready ready 200 true



=== TEST 6: when the control records cannot be created, nothing is usable and it shows
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local json = require("toolkit.json")
            local dict = ngx.shared["tls-session-ticket"]

            ngx.say((state.publish({state = "ready", record = true, source = "external",
                                   revision = 60, keys = h.raws(1)})))

            -- as if the dictionary was full at startup
            dict:flush_all()
            dict:flush_expired()
            local n = 0
            for _, size in ipairs({4000, 1000, 200, 50, 10, 1}) do
                while dict:safe_set("junk" .. n, string.rep("x", size)) do
                    n = n + 1
                end
            end

            ngx.say(state.init())
            ngx.say(state.read())
            ngx.say(state.publish({state = "ready", record = true, source = "external",
                                   revision = 61, keys = h.raws(1)}))
            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(body.status, " ", body.reason, " ", body.key_count, " ",
                    body.last_apply_error)

            dict:flush_all()
            dict:flush_expired()
            ngx.say(state.init())
            local snap = state.read()
            ngx.say(snap.gate, " ", snap.state, " ", #snap.keys)
        }
    }
--- response_body
published
nilfailed to pre-create the control records of shared dict 'tls-session-ticket'
nilcontrol record unavailable
nilfailed to pre-create the control records of shared dict 'tls-session-ticket'
degraded invalid_state 0 control record unavailable
true
none pending 0



=== TEST 7: the worker records are bounded, a record that does not fit shows and evicts nothing
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local json = require("toolkit.json")
            local dict = ngx.shared["tls-session-ticket"]

            ngx.say((state.publish({state = "ready", record = true, source = "external",
                                   revision = 70, keys = h.raws(1, 2)})))
            local snap = state.read()
            local rec = {target_version = snap.version, applied_version = snap.version,
                         contexts = {{id = 1, ok = true}}}

            ngx.say((state.put_worker_record({subsystem = "http", slot = 0, pid = 1001,
                                              generation = 1}, rec)))
            -- a third generation lands on the lane of a live one
            ngx.say(state.put_worker_record({subsystem = "http", slot = 0, pid = 1002,
                                             generation = 3}, rec))
            ngx.say((state.worker_record_failure()))

            local too_many = {contexts = {}}
            for i = 1, state.MAX_CONTEXTS + 1 do
                too_many.contexts[i] = {id = i, ok = true}
            end
            ngx.say(state.put_worker_record({subsystem = "stream", slot = 0, pid = 1001,
                                             generation = 1}, too_many))

            -- no memory left for another record
            local n = 0
            while dict:safe_set("junk" .. n, string.rep("x", 1000)) do
                n = n + 1
            end
            ngx.say(state.put_worker_record({subsystem = "http", slot = 1, pid = 1003,
                                             generation = 1}, rec))
            ngx.say((state.worker_record_failure()))

            -- the snapshot is still complete
            local again = state.read()
            ngx.say(again.version == snap.version, " ", again.state, " ", #again.keys)

            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(body.status, " ", body.reason, " ", body.last_apply_error)

            -- only the owner removes its record
            ngx.say((state.delete_worker_record({subsystem = "http", slot = 0, pid = 1002,
                                                 generation = 1})))
            ngx.say(#state.worker_records())
            ngx.say((state.delete_worker_record({subsystem = "http", slot = 0, pid = 1001,
                                                 generation = 1})))
            ngx.say(#state.worker_records())
        }
    }
--- response_body
published
true
nilworker record slot is in use
no free worker record slot
niltoo many contexts
nilfailed to store the worker record: no memory
no memory for the worker record
true ready 2
degraded invalid_state no memory for the worker record
false
1
true
0



=== TEST 8: a read never assembles a state from mismatching records
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local json = require("toolkit.json")
            local dict = ngx.shared["tls-session-ticket"]

            ngx.say((state.publish({state = "ready", record = true, source = "external",
                                   revision = 80, keys = h.raws(1)})))

            -- the control record moved on but the snapshot did not follow
            local ctl = dict:get("ctl")
            local seq = tonumber(ctl:sub(4, 19))
            dict:safe_set("ctl", ctl:sub(1, 3) .. string.format("%016d", seq + 1)
                                 .. ctl:sub(20))
            ngx.say(state.read())

            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(body.status, " ", body.reason, " ", body.key_count, " ",
                    body.version, " ", body.last_apply_error)

            dict:safe_set("ctl", ctl)
            ngx.say(state.read().state)
        }
    }
--- response_body
published
nilinconsistent
degraded module_not_active 0 nil the SSL layer does not consume the keys
ready



=== TEST 9: concurrent publishers in all the workers never yield a mixed state
--- extra_init_worker_by_lua
    local h = require("lib.ssl_session_ticket")
    local state = require("apisix.session_ticket.state")
    -- odd revisions carry the keys 1 and 2, even ones the key 3
    ngx.timer.at(0, function()
        local deadline = ngx.now() + 3
        local rev = 100 + (ngx.worker.id() or 2)
        while ngx.now() < deadline do
            rev = rev + 1
            local keys = rev % 2 == 1 and h.raws(1, 2) or h.raws(3)
            state.publish({state = "ready", record = true, source = "external",
                           revision = rev, keys = keys})
            ngx.sleep(0)
            ngx.update_time()
        end
    end)
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local status = require("apisix.session_ticket.status")
            local reads, bad, seqs = 0, 0, {}
            local deadline = ngx.now() + 2.5
            while ngx.now() < deadline do
                local snap = state.read()
                if snap and snap.state == "ready" then
                    reads = reads + 1
                    local rev = snap.origin.revision
                    local ok
                    if rev % 2 == 1 then
                        ok = #snap.keys == 2 and snap.keys[1] == h.key(1)
                             and snap.keys[2] == h.key(2)
                    else
                        ok = #snap.keys == 1 and snap.keys[1] == h.key(3)
                    end
                    if not ok then
                        bad = bad + 1
                    end
                    seqs[snap.seq] = rev
                end
                local _, body = status.get()
                if body.status == "ok" or body.status == "off" then
                    bad = bad + 1
                end
                ngx.sleep(0)
                ngx.update_time()
            end
            -- one revision per version
            local revs = {}
            for _, rev in pairs(seqs) do
                if revs[rev] then
                    bad = bad + 1
                end
                revs[rev] = true
            end
            ngx.say("reads: ", reads > 100, " bad: ", bad)
        }
    }
--- response_body
reads: true bad: 0
--- timeout: 10



=== TEST 10: neither the plugin nor the neutral modules depend on the SSL layer
--- config
    location /t {
        content_by_lua_block {
            local function requires(path)
                local f = assert(io.open(path))
                local src = f:read("*a")
                f:close()
                local mods = {}
                for mod in src:gmatch("require%s*%(?%s*[\"']([%w%._%-]+)[\"']") do
                    mods[mod] = true
                end
                for mod in src:gmatch("pcall%(%s*require%s*,%s*[\"']([%w%._%-]+)[\"']") do
                    mods[mod] = true
                end
                return mods
            end

            local function forbidden(mods, patterns)
                local found = {}
                for mod in pairs(mods) do
                    for _, p in ipairs(patterns) do
                        if mod:find(p) then
                            table.insert(found, mod)
                        end
                    end
                end
                table.sort(found)
                return table.concat(found, ",")
            end

            local ssl = {"^apisix%.ssl", "^ngx%.ssl", "^resty%.apisix%.ssl", "^ffi$",
                         "session_ticket%.consumer"}
            local plugins = {"^apisix%.plugin$", "^apisix%.plugins", "^apisix%.stream%.plugins"}

            for _, path in ipairs({"apisix/plugins/ssl-session-ticket.lua",
                                   "apisix/plugins/ssl-session-ticket/record.lua",
                                   "apisix/stream/plugins/ssl-session-ticket.lua"}) do
                ngx.say(path, ": [", forbidden(requires(path), ssl), "]")
            end

            for _, path in ipairs({"apisix/session_ticket/state.lua",
                                   "apisix/session_ticket/status.lua"}) do
                local mods = requires(path)
                ngx.say(path, ": [", forbidden(mods, ssl), "] [",
                        forbidden(mods, plugins), "]")
            end
        }
    }
--- response_body
apisix/plugins/ssl-session-ticket.lua: []
apisix/plugins/ssl-session-ticket/record.lua: []
apisix/stream/plugins/ssl-session-ticket.lua: []
apisix/session_ticket/state.lua: [] []
apisix/session_ticket/status.lua: [] []



=== TEST 11: the adapters publish the record of the Admin API, and a deletion
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local state = require("apisix.session_ticket.state")
            local code = h.put_keys(1, 2)
            local _, rev = h.record()
            local snap = h.wait_state(function(s) return s.origin and s.origin.revision == rev end)
            ngx.say(code, " ", snap.state, " ", #snap.keys, " ", snap.origin.source,
                    " ", snap.keys[1] == h.key(1) and snap.keys[2] == h.key(2))

            -- every adapter has had the time to see it: still one version
            ngx.sleep(2.2)
            local again = state.read()
            ngx.say("once: ", again.version == snap.version
                              and again.updated_at == snap.updated_at)

            code = h.req(h.uri, ngx.HTTP_DELETE)
            snap = h.wait_state(function(s) return s.origin == nil end)
            ngx.say(code, " ", snap.state, " ", #snap.keys)

            -- a late event of the deleted record
            ngx.say((state.publish({state = "ready", record = true, source = "external",
                                   revision = rev, keys = h.raws(1, 2)})))
        }
    }
--- response_body
201 ready 2 external true
once: true
200 empty 0
stale
--- timeout: 15



=== TEST 12: only the Stream subsystem runs the adapter
--- extra_yaml_config
plugins:
  - example-plugin
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
--- stream_conf_enable
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local code = h.put_keys(3)
            local _, rev = h.record()
            local snap = h.wait_state(function(s) return s.origin and s.origin.revision == rev end)
            ngx.say(code, " ", snap.state, " ", #snap.keys, " ", snap.keys[1] == h.key(3))
        }
    }
--- response_body
201 ready 1 true
--- timeout: 15



=== TEST 13: a record the data plane cannot load is unavailable, never half used
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local core = require("apisix.core")
            local json = require("toolkit.json")
            -- written straight into etcd, without the origin only APISIX adds
            core.etcd.set(h.etcd_key, {id = "ssl-session-ticket", keys = h.b64s(4)})
            local _, rev = h.record()
            local snap = h.wait_state(function(s) return s.origin and s.origin.revision == rev end)
            ngx.say(snap.state, " ", #snap.keys, " ", snap.error)
            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(body.status, " ", body.reason, " ", body.source_version == tostring(rev),
                    " ", body.last_apply_error)
            h.req(h.uri, ngx.HTTP_DELETE)
        }
    }
--- response_body
unavailable 0 missing origin
degraded invalid_state true missing origin
--- error_log
is unavailable: missing origin
--- timeout: 15



=== TEST 14: a disabled record publishes no key
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: false
    key_source: external
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local code = h.put_keys(5)
            local _, rev = h.record()
            local snap = h.wait_state(function(s) return s.origin and s.origin.revision == rev end)
            ngx.say(code, " ", snap.state, " ", #snap.keys, " ", snap.origin.disabled)
        }
    }
--- response_body
201 empty 0 true
--- timeout: 15
