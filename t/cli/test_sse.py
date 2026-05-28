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
from threading import Thread
import asyncio
from aiohttp import web
from aiohttp_sse import sse_response
from aiohttp_sse import EventSourceResponse
from datetime import datetime
import time
import pprint
import sseclient
import sys
import os


class SseResponse(EventSourceResponse):
    def __init__(self, **args):
        super().__init__(**args)
        self.headers.pop("X-Accel-Buffering", None)


async def events(request):
    async with sse_response(request, response_cls=SseResponse) as resp:
        for i in range(30000):
            data = "Server Time : {}".format(datetime.now())
            print(data)
            await resp.send(data)
            await asyncio.sleep(1)


def run_server():
    app = web.Application()
    app.router.add_route("GET", "/events", events)
    web.run_app(app, host="127.0.0.1", port=8080)


def run_client():
    time.sleep(2)
    print("start testing sse...")

    def with_requests(url, headers):
        """Get a streaming response for the given event feed using requests."""
        import requests

        return requests.get(url, stream=True, headers=headers)

    url = "http://localhost:9080/events"
    headers = {"Accept": "text/event-stream"}
    response = with_requests(url, headers)
    client = sseclient.SSEClient(response)
    i = 0
    for event in client.events():
        pprint.pprint(event.data)
        i += 1
        if i == 3:
            print("sse proxy test ok")
            os._exit(0)


t = Thread(target=run_client, daemon=True)
t.start()
run_server()
