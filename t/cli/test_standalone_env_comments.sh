#!/usr/bin/env bash

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

. ./t/cli/common.sh

test_tmp=$(mktemp -d)
cp conf/config.yaml "$test_tmp/config.yaml"
cp conf/apisix.yaml "$test_tmp/apisix.yaml"

cleanup_env_test() {
    local status=$?
    trap - EXIT
    if [ "$status" -ne 0 ]; then
        cat logs/error.log || true
    fi
    make stop || true
    cp "$test_tmp/config.yaml" conf/config.yaml
    cp "$test_tmp/apisix.yaml" conf/apisix.yaml
    rm -f "$test_tmp"/*
    rmdir "$test_tmp"
    exit "$status"
}

trap cleanup_env_test EXIT

cat > conf/config.yaml <<'EOF'
apisix:
  enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
EOF

export HOST_IP=127.0.0.1 PORT=9091 NUM=12345
export SINGLE_TEXT="it's 12345"
unset MISSING_COMMENT MISSING_VALUE MISSING_KEY DEFAULT_STATUS
unset MISSING_RELOAD_PLAIN MISSING_RELOAD_QUOTED
upstream_key='${{HOST_IP}}:${{PORT}}'

write_route() {
    local body_yaml="$1"
    local status_yaml="${2:-200}"
    local full_comment="${3:-}"
    local inline_comment="${4:-}"
    cat > conf/apisix.yaml <<EOF
$full_comment
routes:
  - uri: /env-test $inline_comment
    plugins:
      response-rewrite:
        body: $body_yaml
        status_code: $status_yaml
    upstream:
      nodes:
        "$upstream_key": 1
      type: roundrobin
#END
EOF
}

start_config() {
    if ! make init > "$test_tmp/init.log" 2>&1; then
        cat "$test_tmp/init.log"
        echo "failed: make init rejected a valid standalone configuration"
        exit 1
    fi
    if ! make run > "$test_tmp/run.log" 2>&1; then
        cat "$test_tmp/run.log"
        echo "failed: make run rejected a valid standalone configuration"
        exit 1
    fi
}

assert_response() {
    local expected_code="$1"
    local expected_body="$2"
    local match="${3:-exact}"
    local code attempt
    printf '%s' "$expected_body" > "$test_tmp/expected"
    for attempt in $(seq 1 50); do
        code=$(curl -s -m 1 -o "$test_tmp/body" -w '%{http_code}' \
            http://127.0.0.1:9080/env-test || true)
        if [ "$code" = "$expected_code" ]; then
            if [ "$match" = contains ]; then
                if grep -Fq "$expected_body" "$test_tmp/body"; then
                    return
                fi
            elif cmp -s "$test_tmp/expected" "$test_tmp/body"; then
                return
            fi
        fi
        sleep 0.1
    done
    echo "failed: expected HTTP $expected_code and body ($match): $expected_body"
    echo "actual HTTP status: $code"
    cat "$test_tmp/body" || true
    exit 1
}

run_case() {
    start_config
    assert_response "$@"
    make stop
}

assert_init_failure() {
    local expected_error="$1"
    if make init > "$test_tmp/init.log" 2>&1; then
        cat "$test_tmp/init.log"
        echo "failed: make init accepted invalid standalone configuration"
        exit 1
    fi
    if grep -Fq 'stack traceback:' "$test_tmp/init.log"; then
        cat "$test_tmp/init.log"
        echo 'failed: make init raised a Lua stack traceback'
        exit 1
    fi
    if ! grep -Fq 'failed to read local yaml config of apisix:' "$test_tmp/init.log"; then
        cat "$test_tmp/init.log"
        echo 'failed: make init did not use the CLI configuration error handler'
        exit 1
    fi
    if ! grep -Fq "$expected_error" "$test_tmp/init.log"; then
        cat "$test_tmp/init.log"
        echo "failed: missing expected error: $expected_error"
        exit 1
    fi
}

assert_failed_reload() {
    local body_yaml="$1"
    local missing_var="$2"
    local previous_body="$3"
    local recovered_body="$4"
    local recovered_yaml="${5:-$recovered_body}"
    local reload_error_seen=false
    local attempt
    sleep 1
    write_route "$body_yaml"
    for attempt in $(seq 1 50); do
        if grep -F 'failed to parse the content of file ' logs/error.log | \
            grep -Fq "can't find environment variable $missing_var"; then
            reload_error_seen=true
            break
        fi
        sleep 0.1
    done
    if [ "$reload_error_seen" != true ]; then
        echo "failed: runtime reload did not report a controlled error for $missing_var"
        exit 1
    fi
    assert_response 200 "$previous_body"
    sleep 1
    write_route "$recovered_yaml"
    assert_response 200 "$recovered_body"
}

# Check scalar types directly, including cases that are not route schema values.
export A='${{B}}' B=x N=5 FLOAT_VALUE=1.5 BOOL_VALUE=true
export UNSET_REF='${{SECOND_LEVEL_MISSING}}' LIST='[a, b]' ESCAPED='a\nb'
unset SECOND_LEVEL_MISSING EXPLICIT_MISSING
cat > "$test_tmp/scalars.lua" <<'EOF'
local file = require("apisix.cli.file")
local yaml = require("lyaml")
local failures = 0
local function check(name, text, verify)
    local ok, conf, err = pcall(file.load_yaml, text)
    if not ok or not verify(conf, err) then
        io.stderr:write("failed: ", name, ": ", tostring(err or conf), "\n")
        failures = failures + 1
    end
end

for _, scalar in ipairs({"${{A}}", '"${{A}}"', "|-\n  ${{A}}"}) do
    check("single expansion: " .. scalar, "value: " .. scalar, function(conf)
        return conf and conf.value == "${{B}}"
    end)
end
for _, scalar in ipairs({"${{UNSET_REF}}", '"${{UNSET_REF}}"', "|-\n  ${{UNSET_REF}}"}) do
    check("missing second level: " .. scalar, "value: " .. scalar, function(conf)
        return conf and conf.value == "${{SECOND_LEVEL_MISSING}}"
    end)
end
for _, key in ipairs({"${{A}}", '"${{A}}"'}) do
    check("single expansion in key", key .. ": value", function(conf)
        return conf and conf["${{B}}"] == "value"
    end)
end
check("independent scalar occurrences", [[
plain: ${{A}}
quoted: "${{B}}"
block: |-
  ${{B}}
]], function(conf)
    return conf and conf.plain == "${{B}}" and conf.quoted == "x" and conf.block == "x"
end)
check("independent quoted occurrences", 'a: "${{A}}"\nb: "${{B}}"', function(conf)
    return conf and conf.a == "${{B}}" and conf.b == "x"
end)
check("scalar alias expands once", "first: &nested ${{A}}\nsecond: *nested", function(conf)
    return conf and conf.first == "${{B}}" and conf.second == "${{B}}"
end)
check("merge keys retain YAML semantics", [[
base: &base
  body: ${{A}}
value:
  <<: *base
  name: inherited
]], function(conf)
    return conf and conf.value.body == "${{B}}" and conf.value.name == "inherited"
end)
check("substituted string root is rejected", "${{A}}\n#END\n", function(conf, err)
    return conf == nil and err == "invalid apisix.yaml file"
end)
check("scalar alias is not a merge mapping", "first: &s ${{A}}\nvalue:\n  <<: [*s]",
    function(conf, err)
        return conf == nil and err:find("invalid '<<' sequence element", 1, true)
    end)
check("explicit key overrides a merged key", [[
base: &base
  ${{A}}: inherited
value:
  <<: *base
  ${{A}}: override
]], function(conf)
    return conf and conf.value["${{B}}"] == "override"
end)

local tagged = {
    {"!!int ${{N}}", 5},
    {"!!float ${{FLOAT_VALUE}}", 1.5},
    {"!!bool ${{BOOL_VALUE}}", true},
    {"!!null ${{N}}", yaml.null},
    {"!!str ${{N}}", "5"},
    {"!!str ${{A}}", "${{B}}"},
    {"~", yaml.null},
}
for _, case in ipairs(tagged) do
    check(case[1], "value: " .. case[1], function(conf)
        return conf and conf.value == case[2]
    end)
end
check("explicit null missing variable", "value: !!null ${{EXPLICIT_MISSING}}",
    function(conf, err)
        return conf == nil and err == "failed to handle configuration: " ..
            "can't find environment variable EXPLICIT_MISSING"
    end)
check("reject null root", "~\n#END\n", function(conf, err)
    return conf == nil and err == "invalid apisix.yaml file"
end)
check("quoted flow sequence", 'value: ["${{N}}"]', function(conf)
    return conf and conf.value[1] == "5"
end)
check("plain block sequence", "value:\n  - ${{N}}", function(conf)
    return conf and conf.value[1] == 5
end)
check("structure remains data", "value: ${{LIST}}", function(conf)
    return conf and conf.value == "[a, b]"
end)
check("environment escapes remain data", 'value: "${{ESCAPED}}"', function(conf)
    return conf and conf.value == "a\\nb"
end)
check("cyclic alias", "value: &value\n  self: *value", function(conf)
    return conf and conf.value.self == conf.value
end)
assert(failures == 0, tostring(failures) .. " standalone scalar checks failed")
print("passed: standalone scalar types, single expansion, tags, and null roots")
EOF
LUA_PATH="$PWD/?.lua;$PWD/deps/share/lua/5.1/?.lua;$PWD/deps/share/lua/5.1/?/init.lua;;" \
LUA_CPATH="$PWD/deps/lib/lua/5.1/?.so;;" luajit "$test_tmp/scalars.lua"

# Parser-hook errors must reach the ordinary CLI error handler without a traceback.
write_route '${{MISSING_VALUE}}'
assert_init_failure "can't find environment variable MISSING_VALUE"

# Exercise each comment position separately, including generated env declarations.
write_route '"comment-ok"' 200 '# ignored ${{MISSING_COMMENT}}'
run_case 200 comment-ok
if grep -Fq MISSING_COMMENT conf/nginx.conf; then
    echo "failed: a full-line comment exported an environment variable"
    exit 1
fi

write_route '"comment-ok"' 200 '' '# ignored ${{MISSING_COMMENT}}'
run_case 200 comment-ok
if grep -Fq MISSING_COMMENT conf/nginx.conf; then
    echo "failed: an inline comment exported an environment variable"
    exit 1
fi

write_route '"${{NUM}}"'
run_case 200 12345
write_route "'\${{SINGLE_TEXT}}'"
run_case 200 "it's 12345"

NUM=200
write_route '"plain-number-ok"' '${{NUM}}'
run_case 200 plain-number-ok

NUM=12345
write_route $'|-\n          ${{NUM}}'
run_case 200 12345
write_route $'>-\n          ${{NUM}}\n          folded text'
run_case 200 '12345 folded text'

write_route '"default-ok"' '${{DEFAULT_STATUS:=202}}'
run_case 202 default-ok

# Require a successful upstream response, without response-rewrite masking failures.
cat > conf/apisix.yaml <<'EOF'
routes:
  - uri: /env-test
    plugins:
      proxy-rewrite:
        uri: /apisix/nginx_status
    upstream:
      nodes:
        "${{HOST_IP}}:${{PORT}}": 1
      type: roundrobin
#END
EOF
run_case 200 'Active connections:' contains

# Both parser phases must reject invalid reloads and accept later valid changes.
write_route '"reload-ok"'
start_config
assert_response 200 reload-ok
assert_failed_reload '${{MISSING_RELOAD_PLAIN}}' MISSING_RELOAD_PLAIN \
    reload-ok recovered-plain
assert_failed_reload '"${{MISSING_RELOAD_QUOTED}}"' MISSING_RELOAD_QUOTED \
    recovered-plain recovered-quoted '"recovered-quoted"'

sleep 1
printf '~\n#END\n' > conf/apisix.yaml
assert_init_failure 'invalid apisix.yaml file'
reload_error_seen=false
for attempt in $(seq 1 50); do
    if grep -F 'failed to parse the content of file ' logs/error.log | \
        grep -Fq 'invalid apisix.yaml file'; then
        reload_error_seen=true
        break
    fi
    sleep 0.1
done
if [ "$reload_error_seen" != true ]; then
    echo 'failed: runtime accepted a null root document'
    exit 1
fi
assert_response 200 recovered-quoted
sleep 1
write_route '"recovered-null"'
assert_response 200 recovered-null
make stop

# Actual newline bytes in an environment value must survive quoted substitution.
export MULTILINE=$'l1\nl2'
write_route '"${{MULTILINE}}"'
run_case 200 "$MULTILINE"

# Exercise actual PEM environment values through SSL loading and a verified handshake.
if command -v openssl >/dev/null 2>&1; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
        -subj /CN=env-pem.example -keyout "$test_tmp/key.pem" \
        -out "$test_tmp/cert.pem" > "$test_tmp/openssl.log" 2>&1
    export PEM_CERT PEM_KEY
    PEM_CERT=$(cat "$test_tmp/cert.pem")
    PEM_KEY=$(cat "$test_tmp/key.pem")
    for quote in '' '"'; do
        write_route '"pem-ok"'
        sed -i '$d' conf/apisix.yaml
        cat >> conf/apisix.yaml <<EOF
ssls:
  - id: 1
    snis:
      - env-pem.example
    cert: ${quote}\${{PEM_CERT}}${quote}
    key: ${quote}\${{PEM_KEY}}${quote}
#END
EOF
        : > logs/error.log
        start_config
        printf '%s' pem-ok > "$test_tmp/expected"
        tls_ok=false
        for attempt in $(seq 1 50); do
            code=$(curl -sS -m 2 --noproxy '*' --cacert "$test_tmp/cert.pem" \
                --resolve env-pem.example:9443:127.0.0.1 \
                -o "$test_tmp/body" -w '%{http_code}' \
                https://env-pem.example:9443/env-test || true)
            if [ "$code" = 200 ] && cmp -s "$test_tmp/expected" "$test_tmp/body"; then
                tls_ok=true
                break
            fi
            sleep 0.1
        done
        if [ "$tls_ok" != true ] || grep -Fq 'failed to parse cert' logs/error.log; then
            echo 'failed: multiline environment PEM did not serve HTTPS'
            exit 1
        fi
        make stop
    done
else
    echo 'skipped: multiline PEM integration requires openssl'
fi

# Post-parse scalar and key errors must use the same CLI error handler.
for body_yaml in '"${{MISSING_VALUE}}"' $'|-\n          ${{MISSING_VALUE}}'; do
    write_route "$body_yaml"
    assert_init_failure "can't find environment variable MISSING_VALUE"
done

upstream_key='${{MISSING_KEY}}'
write_route '"missing-key"'
assert_init_failure "can't find environment variable MISSING_KEY"

printf 'just-a-scalar\n#END\n' > conf/apisix.yaml
assert_init_failure 'invalid apisix.yaml file'

echo 'passed: standalone scalar substitution, comments, keys, reloads, and startup errors'
