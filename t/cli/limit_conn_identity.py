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

"""Exercise limit-conn through real HTTP, Admin API, etcd, and Redis.

The upstream is an actual HTTP server. Its streaming responses wait for an
explicit release event, so assertions observe requests that are demonstrably
still in flight. No APISIX code or Redis operation is mocked or intercepted.
"""

import argparse
import collections
import http.client
import http.server
import json
import os
from pathlib import Path
import re
import subprocess
import threading
import time
import traceback
import urllib.parse
import uuid


ADMIN_KEY = "test-limit-conn-identity"
REDIS_HOST = os.environ.get("LIMIT_CONN_REDIS_HOST", "127.0.0.1")
REDIS_PORT = int(os.environ.get("LIMIT_CONN_REDIS_PORT", "6379"))
REDIS_DATABASE = 15
RESULT_PATH = Path(os.environ.get(
    "LIMIT_CONN_RESULT_PATH", "logs/limit-conn-identity-results.json"))


def wait_for(check, message, timeout=15):
    deadline = time.monotonic() + timeout
    while True:
        value = check()
        if value:
            return value
        if time.monotonic() >= deadline:
            raise AssertionError(message)
        time.sleep(0.05)


def redis(*arguments, database=REDIS_DATABASE):
    result = subprocess.run(
        ["redis-cli", "--raw", "-h", REDIS_HOST, "-p", str(REDIS_PORT),
         "-n", str(database), *map(str, arguments)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=5)
    return result.stdout.rstrip("\n")


def admin(method, resource, body=None):
    connection = http.client.HTTPConnection("127.0.0.1", 9180, timeout=5)
    try:
        connection.request(method, "/apisix/admin/" + resource,
                           body=json.dumps(body) if body is not None else None,
                           headers={"X-API-KEY": ADMIN_KEY,
                                    "Content-Type": "application/json"})
        response = connection.getresponse()
        data = response.read()
        assert response.status < 300, (method, resource, response.status, data)
        return data
    finally:
        connection.close()


class Upstream(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        request_id = urllib.parse.parse_qs(
            urllib.parse.urlsplit(self.path).query).get("id", [None])[0]
        if self.path.split("?")[0].endswith("/hold"):
            assert request_id
            record = {"path": self.path, "headers": dict(self.headers),
                      "release": threading.Event(), "arrived": time.monotonic()}
            with self.server.record_lock:
                self.server.records[request_id] = record
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.send_header("X-Upstream-Request", request_id)
            self.end_headers()
            self.wfile.write(b"a")
            self.wfile.flush()
            # A deadline prevents a failed test from leaving a handler forever.
            released = record["release"].wait(90)
            record["released"] = released
            try:
                self.wfile.write(b"b")
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")

    def log_message(self, *_):
        pass


class Scenario:
    def __init__(self, name, upstream, report):
        self.name = name
        self.upstream = upstream
        self.report = report
        self.prefix = "lci-" + uuid.uuid4().hex[:16]
        self.resources = []
        self.connections = []
        self.held = []
        self.pools = collections.defaultdict(list)
        etcd_prefix = json.loads(Path("conf/config.yaml").read_text())["deployment"]["etcd"]["prefix"]
        self.counter_pattern = f"limit_conn:{etcd_prefix}/plugin_configs/{self.prefix}:*"
        self.databases = set()
        self.generation = 0
        self.workflow = None
        self.conf = {
            "conn": 2, "burst": 0, "default_conn_delay": 0.1,
            "key": "http_x_tenant", "key_type": "var", "policy": "redis",
            "redis_host": REDIS_HOST, "redis_port": REDIS_PORT,
            "redis_database": REDIS_DATABASE, "redis_timeout": 1000,
            "key_ttl": 60, "rejected_code": 429,
            # Readiness probes load the current configuration without computing
            # a limiter version or consuming quota before the first-hit test.
            "_meta": {"filter": [["http_x_test_probe", "~=", "yes"]]},
        }

    def event(self, kind, **data):
        self.report["events"].append({"time": time.monotonic(),
                                      "kind": kind, **data})

    def put(self, resource, body):
        if resource not in self.resources:
            self.resources.append(resource)
        admin("PUT", resource, body)

    def snapshot(self):
        states = {}
        for database in self.databases:
            for key in redis("KEYS", self.counter_pattern, database=database).splitlines():
                members = redis("ZRANGE", key, 0, -1, database=database).splitlines()
                if members:
                    states[str(database) + ":" + key] = {
                        "database": database, "key": key, "members": members,
                        "ttl": int(redis("PTTL", key, database=database))}
        self.event("redis", states=states)
        return states

    def entries(self):
        return {(state["database"], state["key"], member)
                for state in self.snapshot().values()
                for member in state["members"]}

    def wait_count(self, expected):
        wait_for(lambda: len(self.entries()) == expected,
                 "Redis never reached %s active entries" % expected)

    def request(self, connection, path, headers=None):
        connection.request("GET", "/" + self.prefix + path,
                           headers={"X-Tenant": "tenant-a", "X-Account": "tenant-a",
                                    "X-Other-Tenant": "tenant-b",
                                    "Connection": "keep-alive", **(headers or {})})
        response = connection.getresponse()
        return response

    def fast(self, connection, path="/plain/fast", probe=False):
        response = self.request(connection, path,
                                {"X-Test-Probe": "yes"} if probe else None)
        body = response.read()
        assert response.status == 200 and body == b"ok", (response.status, body)
        return response

    def publish(self, **changes):
        self.conf.update(changes)
        self.databases.add(self.conf["redis_database"])
        self.generation += 1
        plugins = {
            "limit-conn": self.conf,
            "response-rewrite": {"headers": {"set": {
                "X-Limit-Generation": str(self.generation)}}},
        }
        if self.workflow is not None:
            plugins["workflow"] = self.workflow
        self.put("plugin_configs/" + self.prefix, {"plugins": plugins})
        self.wait_generation()
        self.event("published", generation=self.generation, changes=changes)

    def wait_generation(self):
        for pid, pool in self.pools.items():
            def observed():
                response = self.request(pool[0], "/plain/fast", {"X-Test-Probe": "yes"})
                body = response.read()
                assert response.getheader("X-Test-Worker") == pid
                if response.status == 404:
                    return False  # This worker has not received the route yet.
                assert response.status == 200 and body == b"ok", (response.status, body)
                return response.getheader("X-Limit-Generation") == str(self.generation)
            wait_for(observed, "worker did not receive PluginConfig update: " + pid)

    def setup(self):
        self.publish()
        upstream = {"type": "roundrobin", "nodes": {
            "127.0.0.1:" + str(self.upstream.server_port): 1}}
        for route in ["probe", "plain", "sorted"]:
            config = {"uri": "/" + self.prefix + "/" + route + "/*",
                      "upstream": upstream}
            if route != "probe":
                config["plugin_config_id"] = self.prefix
            if route == "sorted":
                config["plugins"] = {"proxy-rewrite": {
                    "headers": {"set": {"X-Sorted-Route": "yes"}},
                    "_meta": {"priority": 100}}}
            self.put("routes/" + self.prefix + "-" + route, config)

        def ready():
            connection = http.client.HTTPConnection("127.0.0.1", 9080, timeout=5)
            try:
                response = self.request(connection, "/probe/fast")
                response.read()
                return response.status == 200
            finally:
                connection.close()
        wait_for(ready, "probe route did not propagate")

        for _ in range(80):
            connection = http.client.HTTPConnection("127.0.0.1", 9080, timeout=20)
            self.connections.append(connection)
            def connected_worker_ready():
                response = self.request(connection, "/probe/fast")
                body = response.read()
                if response.status == 404:
                    return False
                assert response.status == 200 and body == b"ok", (response.status, body)
                return response
            response = wait_for(connected_worker_ready, "worker did not receive probe route")
            pid = response.getheader("X-Test-Worker")
            assert pid, "worker PID header missing"
            self.pools[pid].append(connection)
            if len(self.pools) == 2 and min(map(len, self.pools.values())) >= 4:
                break
        assert len(self.pools) == 2 and min(map(len, self.pools.values())) >= 4, {
            pid: len(pool) for pid, pool in self.pools.items()}
        self.event("workers", connections={pid: len(pool)
                                           for pid, pool in self.pools.items()})
        # Only ordinary-route, filtered probes are used here. They do not
        # initialize conf_version before the opposite first-hit ordering.
        self.wait_generation()
        self.pids = sorted(self.pools)

    def hold(self, worker, index, expected=200, expected_entries=1, headers=None):
        connection = self.pools[self.pids[worker]][index]
        request_id = uuid.uuid4().hex
        before = self.entries()
        response = self.request(connection, "/plain/hold?id=" + request_id, headers)
        assert response.getheader("X-Test-Worker") == self.pids[worker]
        self.event("request", request_id=request_id, status=response.status,
                   worker=self.pids[worker])
        held = {"response": response, "request_id": request_id}
        if response.status == 200:
            self.held.append(held)
            assert response.getheader("X-Upstream-Request") == request_id
            record = self.upstream.records[request_id]
            assert record["headers"]["X-Tenant"] == "tenant-a"
            assert record["headers"]["X-Account"] == "tenant-a"
            assert record["headers"]["X-Other-Tenant"] == "tenant-b"
            for name, value in (headers or {}).items():
                assert record["headers"][name] == value
            self.event("upstream_arrival", request_id=request_id, path=record["path"],
                       arrived=record["arrived"], tenant=record["headers"]["X-Tenant"],
                       account=record["headers"]["X-Account"],
                       other_tenant=record["headers"]["X-Other-Tenant"])
            held["entries"] = self.entries() - before
            assert len(held["entries"]) == expected_entries, held
        else:
            response.read()
            assert request_id not in self.upstream.records, "rejected request reached upstream"
        assert response.status == expected, ("unexpected admission", response.status, expected)
        return held

    def release(self, held):
        self.upstream.records[held["request_id"]]["release"].set()
        assert held["response"].read() == b"ab", "streaming upstream body was corrupted"
        wait_for(lambda: not (held["entries"] & self.entries()),
                 "completed request was not removed from its original Redis key")
        self.held.remove(held)
        self.event("released", request_id=held["request_id"])

    def cleanup(self):
        for held in self.held:
            self.upstream.records[held["request_id"]]["release"].set()
        for connection in self.connections:
            connection.close()
        for resource in reversed(self.resources):
            admin("DELETE", resource)
        for database in self.databases:
            for key in redis("KEYS", self.counter_pattern, database=database).splitlines():
                redis("DEL", key, database=database)


def cleanup_isolation(s):
    # Both PluginConfigs use the same Redis database and resolved subject.
    s.publish(conn=1)
    other = Scenario("cleanup-peer", s.upstream, s.report)
    try:
        other.setup()
        held = s.hold(0, 1)
        assert not other.entries(), "peer snapshot included another PluginConfig's reservation"
        other.release(other.hold(1, 1))
    finally:
        other.cleanup()
    assert s.entries() == held["entries"], "peer cleanup removed the in-flight reservation"
    s.hold(1, 2, 429)
    s.release(held)
    s.release(s.hold(1, 2))
    s.wait_count(0)


def cross_worker(s):
    for worker, order in enumerate([("plain", "sorted"), ("sorted", "plain")]):
        for route in order:
            response = s.fast(s.pools[s.pids[worker]][0], "/" + route + "/fast")
            assert response.getheader("X-Test-Worker") == s.pids[worker]
    s.wait_count(0)
    a = s.hold(0, 1)
    b = s.hold(1, 1)
    s.hold(0, 2, 429)
    s.hold(1, 2, 429)
    assert len(s.snapshot()) == 1, "workers split one policy into separate Redis keys"
    s.release(a)
    c = s.hold(0, 2)
    s.hold(1, 2, 429)
    s.release(b)
    s.release(c)
    s.wait_count(0)


def hot_update(s):
    a = s.hold(0, 1)
    b = s.hold(1, 1)
    original = s.entries()
    s.publish(rejected_code=503, rejected_msg="quota exhausted", redis_timeout=2000,
              default_conn_delay=0.2)
    s.hold(0, 2, 503)
    assert s.entries() == original, "response/connection settings reset active occupancy"
    s.publish(conn=1)
    s.hold(1, 2, 503)
    s.release(a)
    s.hold(0, 2, 503)
    s.release(b)
    c = s.hold(0, 1)
    s.publish(conn=2)
    d = s.hold(1, 1)
    s.hold(0, 2, 503)
    s.release(c)
    assert s.entries() == d["entries"], "old request released another request's entry"
    s.release(d)
    s.wait_count(0)


def mixed_ttl(s):
    a = s.hold(0, 1)
    s.publish(key_ttl=3)
    b = s.hold(1, 1)
    assert len(s.snapshot()) == 1, "changing TTL created a new quota"
    # Advance beyond the new lease while the 60-second old lease is still
    # active. No timing-exact TTL assertion is needed on slow CI runners.
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        assert a["entries"] <= s.entries(), "short TTL removed a longer active lease"
        time.sleep(0.1)
    assert a["entries"] <= s.entries(), "old active lease disappeared"
    # Give the replacement ample time for release assertions on slow runners.
    # The short-lived request is already expired and remains in flight.
    s.publish(key_ttl=60)
    c = s.hold(0, 2)
    s.hold(1, 2, 429)
    s.release(b)
    assert c["entries"] <= s.entries(), "late release removed the replacement request"
    s.release(c)
    assert s.entries() == a["entries"]
    s.release(a)
    s.wait_count(0)


def nonpositive_ttl(s):
    for ttl in (-1, 0):
        s.event("nonpositive_ttl", ttl=ttl, initial_counter="absent")
        s.publish(conn=1, key_ttl=ttl)
        a = s.hold(0, 1, expected_entries=0)
        b = s.hold(1, 1, expected_entries=0)
        assert not s.snapshot(), "non-positive TTL left a counter while requests were in flight"
        s.release(a)
        s.release(b)
        s.wait_count(0)


def nonpositive_ttl_update(s):
    for ttl in (-1, 0):
        s.event("nonpositive_ttl", ttl=ttl, initial_counter="positive_ttl")
        s.publish(conn=2, key_ttl=60)
        a = s.hold(0, 1)
        assert all(state["ttl"] > 0 for state in s.snapshot().values())
        s.publish(key_ttl=ttl)
        b = s.hold(1, 1, expected_entries=0)
        # Preserve EXPIRE's existing non-positive-timeout behavior. Positive
        # leases alone use the new expiry-extension rule.
        assert not s.snapshot(), "non-positive TTL did not delete the existing counter"
        s.release(b)
        s.release(a)
        s.wait_count(0)


def subject_change(s):
    s.publish(conn=1)
    a = s.hold(0, 1)
    s.publish(key="http_x_account")
    s.hold(1, 1, 429)
    assert s.entries() == a["entries"], "expression change discarded the in-flight reservation"
    s.release(a)
    s.wait_count(0)
    b = s.hold(1, 1)
    assert {(db, key) for db, key, _ in a["entries"]} == {
        (db, key) for db, key, _ in b["entries"]}, "same value changed the counter identity"
    s.hold(0, 2, 429)
    s.release(b)
    s.wait_count(0)


def backend_change(s):
    s.publish(conn=1)
    a = s.hold(0, 1)
    s.publish(redis_database=14)
    b = s.hold(1, 1)
    assert {entry[0] for entry in s.entries()} == {14, 15}
    s.release(a)
    assert s.entries() == b["entries"], "old request released the new database's entry"
    s.hold(0, 2, 429)
    s.release(b)
    s.wait_count(0)


def partial_rule_release(s):
    for field in ["conn", "burst", "key", "key_type"]:
        s.conf.pop(field)
    s.publish(rules=[
        {"conn": 2, "burst": 0, "key": "${http_x_tenant}"},
        {"conn": 1, "burst": 0, "key": "${http_x_other_tenant}"},
    ])
    a = s.hold(0, 1, expected_entries=2)
    assert len(s.snapshot()) == 2, "different resolved values shared a counter"
    # Rule 1 admits this request, but rule 2 rejects it. The log phase must
    # release only the partial reservation belonging to the rejected request.
    s.hold(1, 1, 429)
    s.wait_count(2)
    assert s.entries() == a["entries"], "partial admission damaged another request's leases"
    s.release(a)
    s.wait_count(0)


def duplicate_rule_order(s):
    for field in ["conn", "burst", "key", "key_type"]:
        s.conf.pop(field)
    rules = [
        {"conn": "$http_missing", "burst": 0, "key": "${http_x_tenant}"},
        {"conn": 2, "burst": 0, "key": "${http_x_tenant}"},
    ]
    s.publish(rules=rules)
    a = s.hold(0, 1)
    s.publish(rules=list(reversed(rules)))
    b = s.hold(1, 1)
    assert len(s.snapshot()) == 1, "duplicate rule order changed the counter identity"
    assert {(db, key) for db, key, _ in a["entries"]} == {
        (db, key) for db, key, _ in b["entries"]}, "in-flight requests used different counters"
    s.hold(0, 2, 429)
    s.release(a)
    assert s.entries() == b["entries"], "old request released the new request's entry"
    s.release(b)
    s.wait_count(0)


def workflow_isolation(s):
    action = {**s.conf, "conn": 1}
    s.workflow = {"rules": [{
        "case": [["http_x_use_workflow", "==", "yes"]],
        "actions": [["limit-conn", action]],
    }]}
    s.publish(conn=1, key="${http_x_tenant}:1", key_type="var_combination")
    for first, second in [("no", "yes"), ("yes", "no")]:
        first_headers = {"X-Use-Workflow": first}
        second_headers = {"X-Use-Workflow": second}
        a = s.hold(0, 1, headers=first_headers)
        b = s.hold(1, 1, headers=second_headers)
        assert len(s.snapshot()) == 2, "ordinary and workflow counters collided"
        assert a["entries"].isdisjoint(b["entries"])
        s.hold(1, 2, 429, headers=first_headers)
        s.hold(0, 2, 429, headers=second_headers)
        assert s.entries() == a["entries"] | b["entries"]

        # Both paths must retain their occupied counter across an update.
        action["rejected_msg"] = "workflow quota exhausted: " + first
        s.publish(rejected_msg="ordinary quota exhausted: " + first)
        s.hold(1, 2, 429, headers=first_headers)
        s.hold(0, 2, 429, headers=second_headers)
        assert s.entries() == a["entries"] | b["entries"]

        s.release(a)
        assert s.entries() == b["entries"], "release removed the other path's reservation"
        s.hold(0, 2, 429, headers=second_headers)
        c = s.hold(1, 2, headers=first_headers)
        assert {(db, key) for db, key, _ in c["entries"]} == {
            (db, key) for db, key, _ in a["entries"]}
        s.release(b)
        assert s.entries() == c["entries"]
        s.hold(0, 2, 429, headers=first_headers)
        d = s.hold(0, 1, headers=second_headers)
        s.release(c)
        assert s.entries() == d["entries"]
        s.release(d)
        s.wait_count(0)


def write_config():
    config = {
        "apisix": {"node_listen": 9080, "enable_ipv6": False},
        "nginx_config": {
            "worker_processes": 2, "error_log_level": "info",
            "http_server_configuration_snippet":
                "add_header X-Test-Worker $pid always;\nproxy_buffering off;",
            "http": {"keepalive_timeout": "90s"},
        },
        "deployment": {
            "role": "traditional", "role_traditional": {"config_provider": "etcd"},
            "admin": {"admin_key": [{"name": "test", "key": ADMIN_KEY, "role": "admin"}]},
            "etcd": {"host": [os.environ.get("LIMIT_CONN_ETCD_ENDPOINT",
                                             "http://127.0.0.1:2379")],
                     "prefix": "/limit-conn-identity-" + uuid.uuid4().hex},
        },
    }
    Path("conf/config.yaml").write_text(json.dumps(config))


def main():
    cases = {"cross-worker": cross_worker, "hot-update": hot_update,
             "mixed-ttl": mixed_ttl, "nonpositive-ttl": nonpositive_ttl,
             "nonpositive-ttl-update": nonpositive_ttl_update,
             "subject-change": subject_change,
             "backend-change": backend_change, "partial-rule-release": partial_rule_release,
             "duplicate-rule-order": duplicate_rule_order,
             "workflow-isolation": workflow_isolation, "cleanup-isolation": cleanup_isolation}
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-config", action="store_true")
    parser.add_argument("--case", choices=list(cases))
    args = parser.parse_args()
    if args.write_config:
        write_config()
        return 0

    redis("PING")
    def ready():
        try:
            admin("GET", "routes")
            return True
        except (OSError, http.client.HTTPException):
            return False
    wait_for(ready, "APISIX Admin API did not become ready", timeout=30)
    upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
    upstream.records = {}
    upstream.record_lock = threading.Lock()
    thread = threading.Thread(target=upstream.serve_forever, daemon=True)
    thread.start()
    reports = []
    try:
        for name, run in cases.items():
            if args.case and name != args.case:
                continue
            report = {"case": name, "events": [], "passed": False}
            reports.append(report)
            scenario = Scenario(name, upstream, report)
            try:
                scenario.setup()
                run(scenario)
                report["passed"] = True
                print("PASS:", name, flush=True)
            except Exception:
                report["error"] = traceback.format_exc()
                print("FAIL:", name, report["error"], flush=True)
            finally:
                try:
                    scenario.cleanup()
                except Exception:
                    report["passed"] = False
                    report["cleanup_error"] = traceback.format_exc()
                RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
                RESULT_PATH.write_text(json.dumps(reports, indent=2))
    finally:
        upstream.shutdown()
        upstream.server_close()
    if all(report["passed"] for report in reports):
        errors = [line for line in Path("logs/error.log").read_text().splitlines()
                  if re.search(r"\[(error|alert|emerg)\]", line)]
        if errors:
            reports.append({"case": "runtime-log", "passed": False, "errors": errors})
            RESULT_PATH.write_text(json.dumps(reports, indent=2))
            print("FAIL: runtime-log", "\n".join(errors), flush=True)
    return 0 if all(report["passed"] for report in reports) else 1


if __name__ == "__main__":
    raise SystemExit(main())
