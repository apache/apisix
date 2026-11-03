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
"""Close an MCP SSE stream, open another, and see what the gateway does.

An SDK client that calls close() and connects again gets a second session; the
first one has to stop being the client's session without taking the second one
with it.

The last line also records what happens to the session the client walked away
from. The gateway does not learn that an SSE client is gone: writing to the
dropped connection never reports an error without lua_check_client_abort, which
is an http-level directive and not something one plugin gets to turn on for the
whole gateway. The abandoned session therefore stays addressable until its
30-minute lifetime runs out. If that ever changes, this line changes with it.
"""
import json
import sys

import openapi_to_mcp_harness as h


def ping(path, ident):
    status, _, _ = h.post_json(h.GATEWAY, path, {"jsonrpc": "2.0", "id": ident, "method": "ping"})
    return status


def main():
    route = sys.argv[1]
    problems = []

    first = h.SseStream(h.GATEWAY, route)
    if not first.open(timeout=15):
        print("no endpoint on the first stream")
        return
    if ping(first.endpoint, 1) != 202:
        problems.append("the first session did not accept a message")
    if first.wait_for("event: message", timeout=10) is None:
        problems.append("the first session never answered")
    first.close(reset=True)

    second = h.SseStream(h.GATEWAY, route)
    if not second.open(timeout=15):
        problems.append("no endpoint on the second stream")
    else:
        if second.endpoint == first.endpoint:
            problems.append("reconnecting handed out the same session id")
        if ping(second.endpoint, 2) != 202:
            problems.append("the second session did not accept a message")
        event = second.wait_for("event: message", timeout=10)
        if event is None:
            problems.append("the second session never answered")
        elif json.loads(event.split("data: ", 1)[1]).get("id") != 2:
            problems.append("the second session answered with the wrong id")

    unknown = ping(route + "?sessionId=00000000-0000-4000-8000-000000000000", 3)
    if unknown != 404:
        problems.append("an unknown session id returned %s, not 404" % unknown)

    for line in problems:
        print(line)
    print("%d problem(s); the abandoned session answers %s"
          % (len(problems), ping(first.endpoint, 4)))
    second.close(reset=True)


if __name__ == "__main__":
    h.run(main)
