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
"""What a ${...} in base_url or in a header resolves to for an SSE session.

The GET that opens the stream carries the variable's source -- here the
X-User request header. The message POST that follows carries only the session
id, so a value resolved at that point would be empty: the stream has to hand
its own resolution to every message on the session.
"""
import json
import sys

import openapi_to_mcp_harness as h


def main():
    route = sys.argv[1]
    stream = h.SseStream(h.GATEWAY, route, {"X-User": "alice"})
    if not stream.open(timeout=4):
        print("FAIL no endpoint event (%s)" % stream.error)
        return

    # no X-User on this request: the endpoint the client was handed carries
    # nothing but the session id
    status, _, _ = h.post_json(h.GATEWAY, stream.endpoint, {
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": "getPet", "arguments": {"pathParameters": {"petId": 1}}},
    })
    print("post status:", status)

    event = stream.wait_for("event: message", timeout=4)
    if not event:
        print("FAIL no message pushed back")
        return

    result = json.loads(event.split("data: ", 1)[1])["result"]
    upstream = json.loads(result["content"][0]["text"])
    print("upstream saw:", upstream["data"]["seen_auth"])
    stream.close()


if __name__ == "__main__":
    h.run(main)
