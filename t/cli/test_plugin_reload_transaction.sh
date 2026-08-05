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

# The plugin lifecycle across a real gateway process.
#
# t/admin/plugins-reload-transaction.t drives the same transaction inside
# test-nginx, where the plugin set is whatever the block's yaml_config says and
# the process never really starts or stops. This exercises the lifecycle through
# `make run` / the Admin API / `make stop`, so the boot path, the reload path
# and the worker-exit path are the real ones.
#
# Two probe plugins record every init/destroy into the error log, ordered by
# priority: PROBE_A (412) is initialized before PROBE_B (411), so a correct
# unwind destroys B before A. PROBE_BAD (413) sorts ahead of both and its init()
# always throws, which is how the failure scenarios are triggered.

. ./t/cli/common.sh

PROBE_A=t-reload-probe-a
PROBE_B=t-reload-probe-b
PROBE_BAD=t-reload-bad
WORKDIR="$(mktemp -d)"
PLUGIN_DIR="$WORKDIR/apisix/plugins"

mkdir -p "$PLUGIN_DIR"

# Only worker 0 records, so the privileged agent (worker id -1) does not double
# every entry and the sequence stays readable with one worker process.
write_probe() {
    local name="$1"
    local priority="$2"
    cat > "$PLUGIN_DIR/$name.lua" <<EOF
local core = require("apisix.core")
local ngx = ngx

local _M = {
    version = 0.1,
    priority = $priority,
    name = "$name",
    schema = {type = "object", properties = {}},
}

function _M.check_schema(conf)
    return true
end

local function mark(hook)
    if ngx.worker.id() == 0 then
        core.log.warn("plugin-lifecycle: $name ", hook)
    end
end

function _M.init()
    mark("init")
end

function _M.destroy()
    mark("destroy")
end

return _M
EOF
}

# Its destroy() records too: an instance whose init() threw must never be
# destroyed, so seeing it in the sequence is a regression.
write_bad_probe() {
    cat > "$PLUGIN_DIR/$PROBE_BAD.lua" <<EOF
local core = require("apisix.core")
local ngx = ngx

local _M = {
    version = 0.1,
    priority = 413,
    name = "$PROBE_BAD",
    schema = {type = "object", properties = {}},
}

function _M.check_schema(conf)
    return true
end

function _M.init()
    error("$PROBE_BAD: init boom")
end

function _M.destroy()
    if ngx.worker.id() == 0 then
        core.log.warn("plugin-lifecycle: $PROBE_BAD destroy")
    end
end

return _M
EOF
}

write_probe "$PROBE_A" 412
write_probe "$PROBE_B" 411
write_bad_probe

# $1: extra plugin lines, appended to the list
write_config() {
    cat > conf/config.yaml <<EOF
apisix:
  node_listen: 9080
  extra_lua_path: "$WORKDIR/?.lua"
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
nginx_config:
  worker_processes: 1
plugins:
  - response-rewrite
  - $PROBE_A
  - $PROBE_B
$1
EOF
}

# The recorded sequence, comma separated, e.g. "a init,b init,b destroy".
lifecycle_sequence() {
    grep -o "plugin-lifecycle: [a-z0-9-]* [a-z]*" logs/error.log 2>/dev/null \
        | sed 's/plugin-lifecycle: //' \
        | paste -sd, -
}

# Assertions are made on what each step *adds* to the sequence, against a mark
# taken beforehand, so whatever the boot path happens to do stays out of the
# per-step expectations.
MARK=""

# Bounded polling: wait until the sequence stops growing, then mark it.
mark_sequence() {
    local timeout="${1:-15}"
    local deadline=$(( $(date +%s) + timeout ))
    local last="" cur="" stable=0
    { set +x; } 2>/dev/null
    while [ "$(date +%s)" -lt "$deadline" ]; do
        cur="$(lifecycle_sequence)"
        if [ -n "$cur" ] && [ "$cur" = "$last" ]; then
            stable=$(( stable + 1 ))
            if [ "$stable" -ge 5 ]; then
                MARK="$cur"
                set -x
                return 0
            fi
        else
            stable=0
        fi
        last="$cur"
        sleep 0.2
    done
    MARK="$(lifecycle_sequence)"
    set -x
}

# assert_rounds <round> [timeout_secs]
# Waits for the sequence to settle, then requires everything it gained since the
# last mark to be one or more repetitions of <round>.
#
# Not an exact count of rounds on purpose: a deployment that also runs the
# plugin list syncer performs the load more than once per reload, which is
# pre-existing behaviour and not what this file is about. What it asserts is
# that however many rounds run, each one destroys and initializes in the right
# order.
assert_rounds() {
    local round="$1"
    local before="$MARK"
    mark_sequence "${2:-20}"

    local added="${MARK#"$before"}"
    added="${added#,}"

    if [ -z "$added" ]; then
        echo "failed: expected at least one round of '$round', the sequence did not move"
        echo "  full sequence: $MARK"
        exit 1
    fi

    local rest="$added"
    while [ -n "$rest" ]; do
        case "$rest" in
            "$round") rest="" ;;
            "$round",*) rest="${rest#"$round",}" ;;
            *)
                echo "failed: lifecycle sequence mismatch"
                echo "  expected repetitions of: $round"
                echo "  actual added:            $added"
                echo "  full sequence:           $MARK"
                exit 1
                ;;
        esac
    done
}

assert_hello_rewritten() {
    local body
    body="$(curl -s http://127.0.0.1:9080/hello)"
    if [ "$body" != "OLD SET SERVING" ]; then
        echo "failed: the route stopped serving through the old plugin set, got: $body"
        exit 1
    fi
}

reset_state() {
    make stop || true
    etcdctl del / --prefix || true
    rm -f logs/error.log
}

put_route() {
    curl -s -o /dev/null -w '%{http_code}' \
        http://127.0.0.1:9180/apisix/admin/routes/1 -X PUT -d '{
            "uri": "/hello",
            "plugins": {"response-rewrite": {"body": "OLD SET SERVING"}},
            "upstream": {"nodes": {"127.0.0.1:9080": 1}, "type": "roundrobin"}
        }'
}

reload_plugins() {
    curl -s -o /dev/null -w '%{http_code}' \
        http://127.0.0.1:9180/apisix/admin/plugins/reload -X PUT
}

#
# Scenario 1: boot, then a reload that succeeds. The old set is unwound in the
# reverse order of its init() and the new one is initialized in priority order.
#

reset_state
write_config ""
make run
wait_for_tcp 127.0.0.1 9080 20

# the boot sequence itself is not asserted; everything below is asserted as an
# addition to this mark.
mark_sequence 20

code="$(put_route)"
if [ "$code" != "200" ] && [ "$code" != "201" ]; then
    echo "failed: could not create the route, got $code"
    exit 1
fi
sleep 0.5
assert_hello_rewritten

code="$(reload_plugins)"
if [ "$code" != "200" ]; then
    echo "failed: a reload of a loadable plugin set should return 200, got $code"
    exit 1
fi

assert_rounds "$PROBE_B destroy,$PROBE_A destroy,$PROBE_A init,$PROBE_B init"
assert_hello_rewritten

echo "passed: a successful reload unwinds the old set LIFO and re-initializes in order"

#
# Scenario 2: a reload whose plugin set cannot be initialized. The endpoint
# reports it, the previous set keeps serving, and nothing of the new set is
# destroyed -- PROBE_BAD's init() threw, and the new PROBE_A / PROBE_B
# instances were never reached.
#

write_config "  - $PROBE_BAD"

code="$(reload_plugins)"
if [ "$code" != "500" ]; then
    echo "failed: a reload that cannot initialize should return 500, got $code"
    exit 1
fi

# the old instances are destroyed, the rollback re-initializes them in order,
# and no destroy() for PROBE_BAD or for the new probe instances appears
assert_rounds "$PROBE_B destroy,$PROBE_A destroy,$PROBE_A init,$PROBE_B init"

assert_hello_rewritten

if ! grep -q "$PROBE_BAD: init boom" logs/error.log; then
    echo "failed: the failing init() was not reported in the log"
    exit 1
fi

echo "passed: a failed reload is reported, rolled back, and the old set keeps serving"

#
# Scenario 3: the same broken set stays broken and stays harmless. A second
# attempt must behave identically -- in particular the rejected module must not
# have been left in package.loaded, which would make the retry fail for the
# wrong reason and never pick the file up again.
#

code="$(reload_plugins)"
if [ "$code" != "500" ]; then
    echo "failed: the second reload of a broken set should also return 500, got $code"
    exit 1
fi

assert_rounds "$PROBE_B destroy,$PROBE_A destroy,$PROBE_A init,$PROBE_B init"

assert_hello_rewritten

echo "passed: a repeated failed reload stays idempotent"

#
# Scenario 4: recovery. Drop the broken plugin and the next reload succeeds,
# which proves the failures above left no sticky state.
#

write_config ""

code="$(reload_plugins)"
if [ "$code" != "200" ]; then
    echo "failed: a reload should succeed once the broken plugin is gone, got $code"
    exit 1
fi

assert_rounds "$PROBE_B destroy,$PROBE_A destroy,$PROBE_A init,$PROBE_B init"

assert_hello_rewritten

echo "passed: a failed reload leaves no sticky state"

#
# Scenario 5: worker exit unwinds in the same reverse order.
#

make stop

assert_rounds "$PROBE_B destroy,$PROBE_A destroy" 20

echo "passed: worker exit destroys the plugin set in reverse init order"

rm -rf "$WORKDIR"
