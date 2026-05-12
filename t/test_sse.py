from threading import Thread
import asyncio
from aiohttp import web
from aiohttp.web import Response
from aiohttp_sse import sse_response
from aiohttp_sse import EventSourceResponse
from datetime import datetime
import time
import pprint
import sseclient
import sys
import os
import ssl


test_ssl = len(sys.argv) == 2 and sys.argv[1] == "ssl"


class Response(EventSourceResponse):
    def __init__(self, **args):
        super().__init__(**args)
        del self.headers["X-Accel-Buffering"]


async def events(request):
    async with sse_response(request, response_cls=Response) as resp:
        for i in range(30000):
            data = "Server Time : {}".format(datetime.now())
            print(data)
            await resp.send(data)
            await asyncio.sleep(1)


def run_server():
    if test_ssl:
        ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ssl_context.load_cert_chain("t/certs/sse_server.crt", "t/certs/sse_server.key")
    app = web.Application()
    app.router.add_route("GET", "/events", events)
    if test_ssl:
        web.run_app(app, host="127.0.0.1", port=8080, ssl_context=ssl_context)
    else:
        web.run_app(app, host="127.0.0.1", port=8080)


def run_client():
    time.sleep(2)
    print("start testing sse...")

    def with_requests(url, headers):
        """Get a streaming response for the given event feed using requests."""
        import requests

        return requests.get(url, stream=True, headers=headers, verify=False)

    if test_ssl:
        url = "https://localhost:9443/events"
    else:
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
