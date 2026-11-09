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
"""Fire many MCP requests at once and check every answer comes back exactly once.

The MCP SDK client does not wait for one request to finish before sending the
next: it matches answers to requests by id. Both transports have to survive that.

On the SSE transport the risk is real -- the answer to a POST is not written on
that POST's own connection, it is queued in a shared dict and drained by a
separate streaming coroutine that polls. A lost, duplicated or mis-tagged entry
in that queue would be invisible to any test that sends one request at a time.
On the streamable transport each request answers on its own connection, so this
is mostly a check that nothing is stashed in request-shared state.

Prints one line per problem plus a summary the .t asserts on.
"""
import json
import sys
import threading

import openapi_to_mcp_harness as h

# Enough to interleave inside the stream's 0.1s poll, small enough that the
# whole run stays well inside Test::Nginx's budget.
CONCURRENCY = 16


def request_body(index):
    # Mixed methods: a tools/call goes out to the upstream and takes visibly
    # longer than a ping, so answers cannot come back in send order.
    if index % 3 == 0:
        return {"jsonrpc": "2.0", "id": index, "method": "ping"}
    if index % 3 == 1:
        return {"jsonrpc": "2.0", "id": index, "method": "tools/list", "params": {}}
    return {
        "jsonrpc": "2.0", "id": index, "method": "tools/call",
        "params": {"name": "getPet",
                   "arguments": {"pathParameters": {"petId": index}}},
    }


def check_payload(index, payload):
    if not isinstance(payload, dict):
        return "id %r answered with %r" % (index, payload)
    if payload.get("id") != index:
        return "id %r came back as %r" % (index, payload.get("id"))
    if "error" in payload:
        return "id %r answered with an error: %r" % (index, payload["error"])
    if "result" not in payload:
        return "id %r answered without a result" % (index,)
    return None


def fire_all(send):
    """Call send(i) for every index on its own thread, all at once."""
    threads = [threading.Thread(target=send, args=(i,)) for i in range(CONCURRENCY)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=25)


def sse_case(route):
    """One session, CONCURRENCY requests in flight at the same time."""
    stream = h.SseStream(h.GATEWAY, route)
    if not stream.open(timeout=10):
        stream.close()
        return ["sse: no endpoint event (%s)" % stream.error]

    problems = []
    statuses = [None] * CONCURRENCY

    def send(i):
        statuses[i], _, _ = h.post_json(h.GATEWAY, stream.endpoint, request_body(i), timeout=20)

    fire_all(send)
    for index, status in enumerate(statuses):
        if status != 202:
            problems.append("sse: POST for id %d returned %r" % (index, status))

    def all_answers(events):
        return sum(1 for e in events if e.startswith("event: message")) >= CONCURRENCY

    events = stream.wait_until(all_answers, timeout=25)
    stream.close()

    seen = {}
    for event in events:
        if not event.startswith("event: message"):
            continue
        payload = json.loads(event.split("data: ", 1)[1])
        ident = payload.get("id")
        if ident in seen:
            problems.append("sse: id %r answered twice" % (ident,))
        seen[ident] = payload

    for index in range(CONCURRENCY):
        if index not in seen:
            problems.append("sse: id %d never answered" % index)
            continue
        bad = check_payload(index, seen[index])
        if bad:
            problems.append("sse: " + bad)
    return problems


def streamable_case(route):
    """CONCURRENCY independent POSTs on the same route at the same time."""
    answers = [None] * CONCURRENCY

    def send(i):
        status, _, text = h.post_json(h.GATEWAY, route, request_body(i), timeout=20)
        answers[i] = (status, h.first_json(text))

    fire_all(send)
    problems = []
    for index, answer in enumerate(answers):
        if answer is None:
            problems.append("streamable: id %d never answered" % index)
            continue
        status, payload = answer
        if status != 200:
            problems.append("streamable: id %d returned %r (%r)" % (index, status, payload))
            continue
        bad = check_payload(index, payload)
        if bad:
            problems.append("streamable: " + bad)
    return problems


def main():
    sse_route, streamable_route = sys.argv[1], sys.argv[2]
    problems = sse_case(sse_route) + streamable_case(streamable_route)
    for line in problems:
        print(line)
    print("%d problem(s) across %d concurrent requests per transport"
          % (len(problems), CONCURRENCY))


if __name__ == "__main__":
    h.run(main)
