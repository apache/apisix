-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local ffi = require("ffi")
ffi.cdef[[int setenv(const char *, const char *, int); int unsetenv(const char *);]]
local file = require("apisix.cli.file")
local yaml = require("lyaml")

local function set(name, value)
    assert(ffi.C.setenv(name, value, 1) == 0)
end

local pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"
set("CERT_14038", pem)
local crlf = pem:gsub("\n", "\r\n")
set("CRLF_14038", crlf)
set("LIST_14038", "[a,\n b]")
set("TEXT_14038", "hello\nworld")
set("NUM_14038", "0123")
set("ESC_14038", (pem:gsub("\n", "\\n")))
set("BOOL_14038", "true")
set("EMPTY_14038", "")
set("ROOT_14038", "ssls:\n - cert: abc\n")
set("FIELD_14038", "cert")
ffi.C.unsetenv("MISSING_14038")

local failures, total = 0, 0
local function test(name, run)
    total = total + 1
    local ok, err = pcall(run)
    if ok then
        print("PASS " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

local function load(text)
    local conf, err = file.load_yaml_with_env(text)
    assert(conf, err)
    return conf
end

local function old(text)
    local expanded, err = file.resolve_conf_var_in_text(text)
    assert(expanded, err)
    return yaml.load(expanded)
end

local function check(name, text, expected)
    test(name, function()
        local conf = load(text)
        for path, value in pairs(expected) do
            local actual = conf
            for key in path:gmatch("[^.]+") do
                actual = actual[tonumber(key) or key]
            end
            assert(actual == value, path .. ": unexpected value")
        end
    end)
end
local folded = old('cert: "${{CERT_14038}}"').cert
local ssl_pair = {["ssls.1.cert"] = pem, ["ssls.1.key"] = pem}
for _, q in ipairs({'"', "'", ''}) do
    check("certificate and key preserve original bytes quote=" .. q,
          'ssls:\n - cert: ' .. q .. '${{CERT_14038}}' .. q
          .. '\n   key: ' .. q .. '${{CERT_14038}}' .. q .. '\n', ssl_pair)
    check("CRLF certificate quote=" .. q,
          'ssls: [{cert: ' .. q .. '${{CRLF_14038}}' .. q .. '}]',
          {["ssls.1.cert"] = crlf})
end

test("warn only for unprotected SSL references, without exposing values", function()
    local warnings = {}
    local function warn(message)
        warnings[#warnings + 1] = message
        assert(not message:find(pem, 1, true))
    end
    file.load_yaml_with_env('items: ${{LIST_14038}}', warn)
    file.load_yaml_with_env('ssls: [{cert: "${{CERT_14038}}"}]', warn)
    assert(#warnings == 0)
    local text = 'shared: &p "${{CERT_14038}}"\nssls: [{cert: *p}]'
    local conf = file.load_yaml_with_env(text, warn)
    assert(conf.ssls[1].cert == old(text).ssls[1].cert)
    assert(#warnings == 1 and warnings[1]:find("legacy YAML", 1, true))
    conf = file.load_yaml_with_env('shared: &p "${{CERT_14038}}"\n'
        .. 'ssls: [{cert: *p}, {key: "${{CERT_14038}}"}]', warn)
    assert(conf.ssls[2].key == pem and #warnings == 2)
end)

-- Each row is a separate regression: name, source YAML, expected field values.
local cases = {
    {"non-SSL multiline sequences retain their type", 'items: ${{LIST_14038}}',
     {["items.1"] = "a", ["items.2"] = "b"}},
    {"ordinary multiline fields retain folding",
     'other: {cert: "${{TEXT_14038}}", key: "${{TEXT_14038}}"}',
     {["other.cert"] = "hello world", ["other.key"] = "hello world"}},
    {"unquoted flow references and Unicode",
     'note: 中文\nssls: [{cert: ${{CERT_14038}}, key: ${{CERT_14038}}}]',
     {["note"] = "中文", ["ssls.1.cert"] = pem, ["ssls.1.key"] = pem}},
    {"same variable outside SSL is not protected",
     'ssls: [{cert: "${{CERT_14038}}"}]\nother: "${{CERT_14038}}"',
     {["ssls.1.cert"] = pem, other = folded}},
    {"multi-certificate arrays and client CA", [[ssls:
 - certs: [${{CERT_14038}}, "${{CERT_14038}}"]
   keys: [${{CERT_14038}}]
   client: {ca: "${{CERT_14038}}"}
]], {["ssls.1.certs.1"] = pem, ["ssls.1.certs.2"] = pem,
     ["ssls.1.keys.1"] = pem, ["ssls.1.client.ca"] = pem}},
    {"literal backslash-n certificate keeps old result",
     'ssls: [{cert: "${{ESC_14038}}"}]', {["ssls.1.cert"] = pem}},
    {"single-line types and defaults unchanged", [[n: ${{NUM_14038}}
s: "${{NUM_14038}}"
b: ${{BOOL_14038}}
e: ${{EMPTY_14038}}
d: ${{MISSING_14038:=fallback}}
]], {n = 83, s = "0123", b = true, e = yaml.null, d = "fallback"}},
    {"multiline default is protected only in SSL",
     'ssls:\n - cert: "${{MISSING_14038:=line1\nline2}}"\n',
     {["ssls.1.cert"] = "line1\nline2"}},
    {"whole document variable retains legacy behavior", '${{ROOT_14038}}',
     {["ssls.1.cert"] = "abc"}},
    {"single-line variable key selects actual SSL field",
     'ssls:\n - ${{FIELD_14038}}: "${{CERT_14038}}"\n', {["ssls.1.cert"] = pem}},
    {"direct block PEM does not change", 'ssls:\n - cert: |\n     BEGIN\n     DATA\n     END\n',
     {["ssls.1.cert"] = "BEGIN\nDATA\nEND\n"}},
    {"anchors confined to SSL preserve bytes",
     'ssls:\n - cert: &pem "${{CERT_14038}}"\n   key: *pem\n', ssl_pair},
    {"shared non-SSL anchor keeps legacy semantics",
     'shared: &p "${{CERT_14038}}"\nssls:\n - cert: *p\n',
     {shared = folded, ["ssls.1.cert"] = folded}},
    {"merge inside SSL preserves supported fields",
     'ssls:\n - &s {cert: "${{CERT_14038}}"}\n - <<: *s\n',
     {["ssls.1.cert"] = pem, ["ssls.2.cert"] = pem}},
    {"embedded reference retains old behavior",
     'ssls: [{cert: "before-${{TEXT_14038}}-after"}]',
     {["ssls.1.cert"] = "before-hello world-after"}},
}
for _, case in ipairs(cases) do
    check(unpack(case))
end

test("lookup failure still reports missing variable", function()
    local c, err = file.load_yaml_with_env('ssls: [{cert: "${{MISSING_14038}}"}]')
    assert(c == nil and err:find("MISSING_14038", 1, true))
end)

test("raw and escaped marker-like user data remain literal", function()
    local c = load('a: __APISIX_SSL_ENV_1_1__\n'
        .. 'b: "\\x5f_APISIX_SSL_ENV_2_1__"\nssls: [{cert: "${{CERT_14038}}"}]')
    assert(c.a == "__APISIX_SSL_ENV_1_1__" and c.b == "__APISIX_SSL_ENV_2_1__")
    -- An ambiguous discovery may fall back, but must never overwrite user text.
end)

test("marker-looking original content is not interpreted again", function()
    set("ODD_14038", "first\n__APISIX_SSL_ENV_1_2__\n${{NUM_14038}}\n%1")
    local c = load('ssls: [{cert: "${{ODD_14038}}", key: "${{CERT_14038}}"}]')
    assert(c.ssls[1].cert == "first\n__APISIX_SSL_ENV_1_2__\n${{NUM_14038}}\n%1")
end)

test("cyclic aliases do not hang discovery", function()
    local t = 'cycle: &a {self: *a}\nssls: [{cert: "${{CERT_14038}}"}]'
    local c = load(t)
    assert(c.cycle.self == c.cycle)
    assert(c.ssls[1].cert == old(t).ssls[1].cert)
end)

test("top-level scalar retains old folding", function()
    assert(load('"${{TEXT_14038}}"') == "hello world")
end)

test("structural expansion cannot synthesize a protected marker via escapes", function()
    set("INJECT_14038", 'text"\n   key: "\\x5f_APISIX_SSL_ENV_1_1__')
    local t = 'ssls:\n - cert: "${{CERT_14038}}"\n   x: "${{INJECT_14038}}"\n'
    local warnings = 0
    local c = file.load_yaml_with_env(t, function() warnings = warnings + 1 end)
    assert(c.ssls[1].key == "__APISIX_SSL_ENV_1_1__" and warnings == 1)
end)

print("RESULT " .. (total - failures) .. "/" .. total .. " passed")
assert(failures == 0, failures .. " regression tests failed")
