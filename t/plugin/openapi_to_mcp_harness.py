#!/usr/bin/env python3
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
"""Plumbing shared by the openapi-to-mcp test drivers in this directory."""
import http.client
import json
import socket
import struct
import sys
import threading
import traceback
import urllib.parse

GATEWAY = ("127.0.0.1", 1984)
BOTH = "application/json, text/event-stream"
JSON_HEADERS = {"Content-Type": "application/json", "Accept": BOTH}


def merge(base, overrides):
    """Apply header overrides; a value of None removes the header."""
    headers = dict(base or {})
    for key, value in (overrides or {}).items():
        if value is None:
            headers.pop(key, None)
        else:
            headers[key] = value
    return headers


def request(target, method, path, body=None, headers=None, timeout=10):
    """One HTTP exchange.

    Returns (status, headers, text), headers lower-cased. status is None when the
    exchange itself failed, and text then says why.
    """
    host, port = target
    conn = http.client.HTTPConnection(host, port, timeout=timeout)
    data = None
    if body is not None:
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
    try:
        conn.request(method, path, body=data, headers=headers or {})
        resp = conn.getresponse()
        text = resp.read().decode(errors="replace")
        return resp.status, {k.lower(): v for k, v in resp.getheaders()}, text
    except Exception as exc:                                # noqa: BLE001
        return None, {}, "transport error: %r" % (exc,)
    finally:
        conn.close()


def post_json(target, path, body, headers=None, timeout=10):
    """POST a JSON-RPC message the way a client would."""
    return request(target, "POST", path, body, merge(JSON_HEADERS, headers), timeout)


def first_json(text):
    """The first JSON payload in a reply, SSE-framed or not, else None."""
    for line in (text or "").splitlines():
        line = line[6:] if line.startswith("data: ") else line
        if line[:1] in ("{", "["):
            try:
                return json.loads(line)
            except ValueError:
                return None
    return None


class SseStream:
    """One open SSE connection, collecting its events on a background thread."""

    def __init__(self, target, path, headers=None):
        self.target, self.path = target, path
        self.headers = merge({"Accept": "text/event-stream"}, headers)
        self.events = []
        self.cond = threading.Condition()
        self.stop = threading.Event()
        self.conn = None
        self.error = None
        self.endpoint = None
        self.session_id = None

    def _read(self):
        try:
            self.conn = http.client.HTTPConnection(*self.target, timeout=30)
            self.conn.request("GET", self.path, headers=self.headers)
            resp = self.conn.getresponse()
            if resp.status != 200:
                raise RuntimeError("stream status %d" % resp.status)
            buf = b""
            while not self.stop.is_set():
                chunk = resp.read(1)
                if not chunk:
                    break
                buf += chunk
                if buf.endswith(b"\n\n"):
                    with self.cond:
                        self.events.append(buf.decode().strip())
                        self.cond.notify_all()
                    buf = b""
        except Exception as exc:                            # noqa: BLE001
            if not self.stop.is_set():
                self.error = "stream: %s" % (exc,)
            with self.cond:
                self.cond.notify_all()

    def open(self, timeout=8):
        """Start reading and wait for the endpoint event. False if none came."""
        threading.Thread(target=self._read, daemon=True).start()
        event = self.wait_for("event: endpoint", timeout)
        if not event:
            return False
        self.endpoint = event.split("data: ", 1)[1].strip()
        query = urllib.parse.urlparse(self.endpoint).query
        self.session_id = urllib.parse.parse_qs(query).get("sessionId", [None])[0]
        return self.session_id is not None

    def wait_until(self, predicate, timeout):
        """Wait until predicate(events) holds; returns a snapshot of the events."""
        with self.cond:
            self.cond.wait_for(lambda: self.error is not None or predicate(self.events),
                               timeout=timeout)
            return list(self.events)

    def wait_for(self, prefix, timeout=6, after=0):
        """The first event after index `after` that starts with prefix, else None."""
        def found(events):
            return any(e.startswith(prefix) for e in events[after:])

        events = self.wait_until(found, timeout)
        return next((e for e in events[after:] if e.startswith(prefix)), None)

    def close(self, reset=False):
        """Drop the connection without draining it.

        HTTPConnection.close() reads the rest of the response first, which on a
        stream that stays open means waiting for the server's keepalive to fail.
        With reset=True the socket is closed with an RST instead of a FIN.
        """
        self.stop.set()
        sock = getattr(self.conn, "sock", None)
        if sock is None:
            return
        try:
            if reset:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
            else:
                sock.shutdown(socket.SHUT_RDWR)
            sock.close()
        except OSError:
            pass


def run(main):
    """Run a driver's main and always exit 0.

    Test::Nginx discards an --- exec block's stdout entirely when the command
    exits non-zero, which turns a failure into an empty body with no clue in
    it. A driver says what happened in what it prints instead.
    """
    try:
        main()
    except Exception:                                       # noqa: BLE001
        print("harness error:")
        traceback.print_exc(file=sys.stdout)
    sys.stdout.flush()
    sys.exit(0)


def rpc_main():
    """openapi_to_mcp_harness.py PATH MESSAGE CODE

    POST one JSON-RPC message to the gateway the way a client would, then run
    CODE with the reply's JSON payload bound to d, for a .t to assert on what
    CODE prints.
    """
    path, message, code = sys.argv[1:4]
    _, _, text = post_json(GATEWAY, path, message)
    exec(code, {"json": json, "d": first_json(text)})


if __name__ == "__main__":
    run(rpc_main)
