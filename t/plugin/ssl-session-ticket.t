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

=== TEST 1: generated keys are not writable through the Admin API
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: true
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local code, body = h.put_keys(1)
            ngx.say(code, " ", body)
            code, body = h.req(h.uri, ngx.HTTP_DELETE)
            ngx.say(code, " ", body)
            ngx.say(select(2, h.record()))
        }
    }
--- response_body
409 {"error_msg":"the keys of ssl-session-ticket are maintained by the built-in generator because plugin_attr.ssl-session-ticket.key_source is generated; set it to external to manage the keys through the Admin API"}
409 {"error_msg":"the keys of ssl-session-ticket are maintained by the built-in generator because plugin_attr.ssl-session-ticket.key_source is generated; set it to external to manage the keys through the Admin API"}
404



=== TEST 2: PUT the complete set of keys, stored encrypted with an origin
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local core = require("apisix.core")
            local code, body = h.put_keys(1, 2)
            ngx.say(code, " leak: ", h.leaks(body, 1, 2))
            local res = core.json.decode(body)
            ngx.say(res.key, " ", core.json.encode(res.value.keys))

            local value = h.record()
            ngx.say("stored in clear: ", h.leaks(value, 1, 2))
            local plain = {}
            for i, k in ipairs(value.keys) do
                plain[i] = core.data_encryption.decrypt(k)
            end
            ngx.say("decrypted: ", plain[1] == h.b64(1) and plain[2] == h.b64(2))
            ngx.say("origin: ", value.origin.source, " ", value.origin.disabled, " ",
                    value.origin.policy)
            -- the response does not leak the stored ciphertext either
            ngx.say("ciphertext in response: ",
                    core.string.find(body, value.keys[1]) ~= nil)
        }
    }
--- response_body_like
201 leak: false
/apisix/plugin_metadata/ssl-session-ticket \["<redacted>","<redacted>"\]
stored in clear: false
decrypted: true
origin: external false [0-9a-f]{8}
ciphertext in response: false



=== TEST 3: GET and the list are redacted, the other metadata are not
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            local code, body = h.req("/apisix/admin/plugin_metadata/example-plugin",
                                     ngx.HTTP_PUT, {skey = "val", ikey = 1})
            ngx.say(code)

            code, body = h.req(h.uri, ngx.HTTP_GET)
            ngx.say(code, " leak: ", h.leaks(body, 1, 2))
            body = json.decode(body)
            ngx.say(json.encode(body.value.keys))

            code, body = h.req("/apisix/admin/plugin_metadata", ngx.HTTP_GET)
            ngx.say(code, " leak: ", h.leaks(body, 1, 2))
            body = json.decode(body)
            for _, item in ipairs(body.list) do
                if item.value.id == "ssl-session-ticket" then
                    ngx.say(json.encode(item.value.keys))
                else
                    ngx.say(item.value.id, " ", item.value.skey)
                end
            end
        }
    }
--- response_body
201
200 leak: false
["<redacted>","<redacted>"]
200 leak: false
example-plugin val
["<redacted>","<redacted>"]



=== TEST 4: the same keys in the same order write nothing, another order does
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local _, rev1 = h.record()
            local code = h.put_keys(1, 2)
            local _, rev2 = h.record()
            ngx.say(code, " unchanged: ", rev1 == rev2)

            code = h.put_keys(2, 1)
            local value, rev3 = h.record()
            ngx.say(code, " changed: ", rev3 > rev2)

            code = h.put_keys(2, 1)
            local _, rev4 = h.record()
            ngx.say(code, " unchanged: ", rev3 == rev4)
        }
    }
--- response_body
200 unchanged: true
200 changed: true
200 unchanged: true



=== TEST 5: invalid requests are rejected as a whole and never partially written
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local core = require("apisix.core")
            local before, rev_before = h.record()

            local same_name = ngx.encode_base64(string.sub(h.key(1), 1, 16)
                                                .. string.rep("z", 64))
            local too_many = {}
            for i = 1, 257 do
                too_many[i] = h.b64(i)
            end

            local cases = {
                {keys = h.b64s(3), enabled = true},
                {keys = h.b64s(3), key_source = "external"},
                {keys = h.b64s(3), rotation_interval = 60},
                {keys = h.b64s(3), max_keys = 3},
                {keys = h.b64s(3), origin = {source = "external", disabled = false}},
                {keys = h.b64s(3), id = "ssl-session-ticket"},
                {keys = h.b64s(3), not_after = 1793072518},
                {keys = {{key = h.b64(3), expire = 1793072518}}},
                {keys = {"ref:" .. h.b64(3)}},
                {keys = h.b64(3)},
                {keys = {h.b64(3), "not base64!"}},
                {keys = {h.b64(3), ngx.encode_base64(string.rep("x", 79))}},
                {keys = h.b64s(3, 4, 3)},
                {keys = {h.b64(1), same_name}},
                {keys = too_many},
            }
            for _, case in ipairs(cases) do
                local code, body = h.req(h.uri, ngx.HTTP_PUT, case)
                ngx.say(code, " ", body)
                if h.leaks(body, 1, 2, 3, 4) then
                    ngx.say("leaked")
                end
            end

            local code, body = h.req(h.uri, ngx.HTTP_PUT, "{}")
            ngx.say(code, " ", body)

            local after, rev_after = h.record()
            ngx.say("unchanged: ", rev_before == rev_after
                    and core.json.encode(before) == core.json.encode(after))
        }
    }
--- response_body
400 {"error_msg":"invalid configuration: additional properties forbidden, found enabled"}
400 {"error_msg":"invalid configuration: additional properties forbidden, found key_source"}
400 {"error_msg":"invalid configuration: additional properties forbidden, found rotation_interval"}
400 {"error_msg":"invalid configuration: additional properties forbidden, found max_keys"}
400 {"error_msg":"invalid configuration: additional properties forbidden, found origin"}
400 {"error_msg":"invalid configuration: additional properties forbidden, found id"}
400 {"error_msg":"invalid configuration: additional properties forbidden, found not_after"}
400 {"error_msg":"invalid configuration: property \"keys\" validation failed: failed to validate item 1: wrong type: expected string, got table"}
400 {"error_msg":"invalid configuration: keys[1] is not valid base64"}
400 {"error_msg":"invalid configuration: property \"keys\" validation failed: wrong type: expected array, got string"}
400 {"error_msg":"invalid configuration: keys[2] is not valid base64"}
400 {"error_msg":"invalid configuration: keys[2] must be the base64 of 80 bytes"}
400 {"error_msg":"invalid configuration: keys[3] duplicates keys[1]"}
400 {"error_msg":"invalid configuration: keys[2] has the same key name (first 16 bytes) as keys[1]"}
400 {"error_msg":"invalid configuration: property \"keys\" validation failed: expect array to have at most 256 items"}
400 {"error_msg":"invalid configuration: property \"keys\" is required"}
unchanged: true



=== TEST 6: a body that is not JSON is neither echoed nor logged
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local code, body = h.req(h.uri, ngx.HTTP_PUT,
                                     '{"keys": ["' .. h.b64(5) .. '"')
            ngx.say(code, " leak: ", h.leaks(body, 5))
            ngx.say(body)
        }
    }
--- response_body
400 leak: false
{"error_msg":"invalid request body: Expected comma or array end but found T_END at character 121"}
--- error_log
invalid request body of plugin_metadata/ssl-session-ticket, err: Expected comma or array end
--- no_error_log
dGlja2V0LW5hbWUtMDAwNUZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkY=



=== TEST 7: no TTL on the keys
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local code, body = h.req(h.uri .. "?ttl=60", ngx.HTTP_PUT, {keys = h.b64s(6)})
            ngx.say(code, " ", body)
        }
    }
--- response_body
400 {"error_msg":"ttl is not supported for ssl-session-ticket"}



=== TEST 8: the record is disabled when the local policy is
--- extra_yaml_config
plugin_attr:
  ssl-session-ticket:
    enabled: false
    key_source: external
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local _, rev1 = h.record()
            local code = h.put_keys(2, 1)
            local value, rev2 = h.record()
            ngx.say(code, " disabled: ", value.origin.disabled, " new revision: ", rev2 > rev1)
        }
    }
--- response_body
200 disabled: true new revision: true



=== TEST 9: the same keys under another local policy are written again
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local _, rev1 = h.record()
            local code = h.put_keys(2, 1)
            local value, rev2 = h.record()
            ngx.say(code, " disabled: ", value.origin.disabled, " new revision: ", rev2 > rev1)
        }
    }
--- response_body
200 disabled: false new revision: true



=== TEST 10: writes are atomic against the revision read
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local core = require("apisix.core")
            local metadata = require("apisix.admin.plugin_metadata")

            -- another writer commits between the read and the write
            local get = core.etcd.get
            core.etcd.get = function(key, ...)
                local res, err = get(key, ...)
                core.etcd.set(h.etcd_key, res.body.node.value)
                return res, err
            end

            local code, body = metadata:put("ssl-session-ticket", {keys = h.b64s(7)})
            ngx.say(code, " ", core.json.encode(body))
            code, body = metadata:delete("ssl-session-ticket", nil, nil, {})
            ngx.say(code, " ", core.json.encode(body))
            core.etcd.get = get

            local value = h.record()
            ngx.say("keys: ", #value.keys)
        }
    }
--- response_body
409 {"error_msg":"ssl-session-ticket metadata was changed concurrently, retry the request"}
409 {"error_msg":"ssl-session-ticket metadata was changed concurrently, retry the request"}
keys: 2



=== TEST 11: DELETE removes the record
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local code, body = h.req(h.uri, ngx.HTTP_DELETE)
            body = require("toolkit.json").decode(body)
            ngx.say(code, " ", body.deleted, " ", body.key)
            ngx.say(select(2, h.record()))
            code = h.req(h.uri, ngx.HTTP_DELETE)
            ngx.say(code)
            code = h.req(h.uri, ngx.HTTP_GET)
            ngx.say(code)
        }
    }
--- response_body
200 1 /apisix/plugin_metadata/ssl-session-ticket
404
404
404



=== TEST 12: an empty array is a valid set
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local code = h.req(h.uri, ngx.HTTP_PUT, '{"keys": []}')
            local value = h.record()
            ngx.say(code, " ", require("toolkit.json").encode(value.keys))
        }
    }
--- response_body
201 []



=== TEST 13: without data encryption the keys are stored as given and it is reported
--- extra_yaml_config
apisix:
  data_encryption:
    enable_encrypt_fields: false
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            local code = h.put_keys(8)
            local value = h.record()
            ngx.say(code, " ", value.keys[1] == h.b64(8))
            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            ngx.say(json.encode(json.decode(body).warnings))
        }
    }
--- response_body
200 true
["encryption_disabled"]
--- error_log
apisix.data_encryption.enable_encrypt_fields is false, the TLS session ticket keys are stored in etcd in clear text



=== TEST 14: keys stored in clear are not used once encryption is on, nor logged
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            local snap = h.wait_state(function(s) return s.state ~= "pending" end)
            ngx.say(snap.state, " ", #snap.keys)
            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            body = json.decode(body)
            ngx.say(body.status, " ", body.reason, " ", body.last_apply_error)
            ngx.say(json.encode(body.warnings))
            -- leave a clean state for the next tests
            ngx.say((h.req(h.uri, ngx.HTTP_DELETE)))
        }
    }
--- response_body
unavailable 0
degraded invalid_state keys[1] can not be decrypted with the data_encryption keyring
["default_keyring"]
200
--- error_log
the ssl-session-ticket record of revision
is unavailable: keys[1] can not be decrypted with the data_encryption keyring
the TLS session ticket keys are encrypted with the default public apisix.data_encryption.keyring
--- no_error_log
dGlja2V0LW5hbWUtMDAwOE



=== TEST 15: a private keyring is not
--- extra_yaml_config
apisix:
  data_encryption:
    keyring:
      - 0123456789abcdef
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local json = require("toolkit.json")
            local _, body = h.req("/v1/tls_session_ticket", ngx.HTTP_GET)
            ngx.say(json.encode(json.decode(body).warnings))
        }
    }
--- response_body
[]
--- no_error_log
default public apisix.data_encryption.keyring



=== TEST 16: a complete record is validated without leaking keys, as a standalone configuration
--- config
    location /t {
        content_by_lua_block {
            local h = require("lib.ssl_session_ticket")
            local cases = {
                {id = "ssl-session-ticket", keys = h.b64s(9)},
                {id = "ssl-session-ticket", keys = h.b64s(9),
                 origin = {source = "external", disabled = true}},
                {id = "ssl-session-ticket", keys = h.b64s(9), enabled = true},
                {id = "ssl-session-ticket", keys = h.b64s(9),
                 origin = {source = "generated", disabled = false}},
                {id = "ssl-session-ticket", keys = h.b64s(9, 9)},
            }
            for _, case in ipairs(cases) do
                local code, body = h.req("/apisix/admin/configs/validate", ngx.HTTP_POST,
                                         {plugin_metadata = {case}})
                ngx.say(code, " leak: ", h.leaks(body, 9))
            end
        }
    }
--- response_body
200 leak: false
200 leak: false
400 leak: false
400 leak: false
400 leak: false
