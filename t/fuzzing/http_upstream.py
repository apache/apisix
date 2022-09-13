#! /usr/bin/env python

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

# This file provides a fuzzing test with different upstreams
import http.client
import json
import random
import threading
from public import check_leak, run_test, connect_admin


REQ_PER_THREAD = 50
THREADS_NUM = 4
TOTOL_ROUTES = 10


def create_route():
    for i in range(TOTOL_ROUTES):
        conn = connect_admin()
        scheme = "http" if i % 2 == 0 else "https"
        port = ":6666" if i % 2 == 0 else ":6667"
        suffix = str(i + 1)
        i = str(i)
        conf = json.dumps({
            "uri": "/*",
            "host": "test" + i + ".com",
            "plugins": {
            },
            "upstream": {
                "scheme": scheme,
                "nodes": {
                    "127.0.0." + suffix + port: 1
                },
                "type": "roundrobin"
            },
        })

        conn.request("PUT", "/apisix/admin/routes/" + i, conf,
                headers={
                    "X-API-KEY":"edd1c9f034335f136f87ad84b625c8f1",
                })
        response = conn.getresponse()
        assert response.status <= 300, response.read()

def req():
    route_id = random.randrange(TOTOL_ROUTES)
    conn = http.client.HTTPConnection("127.0.0.1", port=9080)
    conn.request("GET", "/server_addr",
            headers={
                "Host":"test" + str(route_id) + ".com",
            })
    response = conn.getresponse()
    assert response.status == 200, response.read()
    ip = response.read().rstrip().decode()
    suffix = str(route_id + 1)
    assert "127.0.0." + suffix == ip, f"expect: 127.0.0.{suffix}, actual: {ip}"

def run_in_thread():
    for i in range(REQ_PER_THREAD):
        req()

@check_leak
def run():
    th = [threading.Thread(target=run_in_thread) for i in range(THREADS_NUM)]
    for t in th:
        t.start()
    for t in th:
        t.join()


if __name__ == "__main__":
    run_test(create_route, run)

