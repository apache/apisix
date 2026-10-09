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
"""Open an SSE stream on one route and try to use its session on another.

The session id a stream hands out is a bearer credential for that stream. It is
issued by one route, and a message endpoint on a second route must not accept
it: doing so would let anyone who learns the id push a tool result into someone
else's stream, with the second route's configuration behind it.
"""
import sys

import openapi_to_mcp_harness as h

PING = {"jsonrpc": "2.0", "id": 1, "method": "ping"}


def main():
    own, other = sys.argv[1], sys.argv[2]
    stream = h.SseStream(h.GATEWAY, own)
    if not stream.open(timeout=6):
        print("FAIL no endpoint event (%s)" % stream.error)
        return

    _, _, query = stream.endpoint.partition("?")
    own_status, _, _ = h.post_json(h.GATEWAY, stream.endpoint, PING)
    other_status, _, _ = h.post_json(h.GATEWAY, other + "?" + query, PING)

    print("own route:", own_status)
    print("other route:", other_status)
    print("pushed on own stream:", stream.wait_for("event: message", timeout=3) is not None)
    stream.close()


if __name__ == "__main__":
    h.run(main)
