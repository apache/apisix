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
"""Drive several concurrent MCP SSE sessions against a multi-worker gateway.

The GET that opens a stream and the POST that feeds it are separate connections,
so with more than one nginx worker they routinely land on different processes.
Session state therefore has to live in shared memory, not in a worker-local Lua
table -- a single-worker test cannot tell the two apart.

Prints one line per failed session plus a summary the .t asserts on.
"""
import json
import sys
import threading

import openapi_to_mcp_harness as h


def one_session(route, index):
    stream = h.SseStream(h.GATEWAY, route)
    try:
        if not stream.open(timeout=10):
            return "session %d: no endpoint event (%s)" % (index, stream.error)
        status, _, _ = h.post_json(h.GATEWAY, stream.endpoint,
                                   {"jsonrpc": "2.0", "id": index, "method": "ping"})
        if status != 202:
            return "session %d: post returned %s" % (index, status)
        event = stream.wait_for("event: message", timeout=10)
        if not event:
            return "session %d: answer never came back on the stream" % index
        got = json.loads(event.split("data: ", 1)[1]).get("id")
        if got != index:
            return "session %d: got id %r" % (index, got)
        return None
    finally:
        stream.close()


def main():
    route = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 6

    results = [None] * count

    def drive(i):
        results[i] = one_session(route, i + 1)

    threads = [threading.Thread(target=drive, args=(i,)) for i in range(count)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30)

    failures = [r for r in results if r]
    for line in failures:
        print(line)
    print("ok %d/%d sessions" % (count - len(failures), count))


if __name__ == "__main__":
    h.run(main)
