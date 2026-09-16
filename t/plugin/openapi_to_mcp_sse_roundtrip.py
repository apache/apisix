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
"""Drive one full MCP SSE round trip against the gateway.

Opens the GET stream, reads the endpoint event to learn the session id, POSTs a
JSON-RPC request to the advertised message endpoint, then reads the answer back
off the stream. Prints a fixed set of lines the .t asserts on.
"""
import json
import sys

import openapi_to_mcp_harness as h


def main():
    route = sys.argv[1]
    stream = h.SseStream(h.GATEWAY, route)
    if not stream.open(timeout=4):
        print("FAIL no endpoint event (%s)" % stream.error)
        return

    path, _, query = stream.endpoint.partition("?")
    print("endpoint path:", path)
    print("has sessionId:", query.startswith("sessionId=") and len(query) > 10)

    status, _, _ = h.post_json(h.GATEWAY, stream.endpoint, {
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                   "clientInfo": {"name": "probe", "version": "1"}},
    })
    print("post status:", status)

    event = stream.wait_for("event: message", timeout=2)
    if not event:
        print("FAIL no message pushed back")
        return
    result = json.loads(event.split("data: ", 1)[1])["result"]
    print("protocolVersion:", result["protocolVersion"])
    print("serverInfo:", result["serverInfo"]["name"], result["serverInfo"]["version"])

    # a message for an unknown session must be rejected
    bad, _, _ = h.post_json(h.GATEWAY, path + "?sessionId=does-not-exist",
                            {"jsonrpc": "2.0", "id": 2, "method": "ping"})
    print("unknown session status:", bad)
    stream.close()


if __name__ == "__main__":
    h.run(main)
