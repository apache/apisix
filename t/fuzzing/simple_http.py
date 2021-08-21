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

# This file provides a fuzzing test with most common plugins via plain HTTP request
import http.client
import json
import random
import threading
from public import check_leak, LEAK_COUNT, run_test


REQ_PER_THREAD = 50
THREADS_NUM = 10
TOTOL_ROUTES = 50


def create_route():
    conf = json.dumps({
        "username": "jack",
        "plugins": {
            "jwt-auth": {
                "key": "user-key",
                "secret": "my-secret-key"
            }
        }
    })
    conn = http.client.HTTPConnection("127.0.0.1", port=9080)
    conn.request("PUT", "/apisix/admin/consumers", conf,
            headers={
                "X-API-KEY":"edd1c9f034335f136f87ad84b625c8f1",
            })
    response = conn.getresponse()
    assert response.status <= 300, response.read()

    for i in range(TOTOL_ROUTES):
        conn = http.client.HTTPConnection("127.0.0.1", port=9080)
        i = str(i)
        conf = json.dumps({
            "uri": "/*",
            "host": "test" + i + ".com",
            "plugins": {
                "limit-count": {
                    "count": LEAK_COUNT * REQ_PER_THREAD * THREADS_NUM,
                    "time_window": 3600,
                },
                "jwt-auth": {
                },
                "proxy-rewrite": {
                    "uri": "/" + i,
                    "headers": {
                        "X-APISIX-Route": "apisix-" + i
                    }
                },
                "response-rewrite": {
                    "headers": {
                        "X-APISIX-Route": "$http_x_apisix_route"
                    }
                },
            },
            "upstream": {
                "nodes": {
                    "127.0.0.1:6666": 1
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
    jwt_token = ("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."+
        "eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0."+
        "fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs")
    route_id = str(random.randrange(TOTOL_ROUTES))
    conn = http.client.HTTPConnection("127.0.0.1", port=9080)
    conn.request("GET", "/",
            headers={
                "Host":"test" + route_id + ".com",
                "Authorization":jwt_token,
            })
    response = conn.getresponse()
    assert response.status == 200, response.read()
    hdr = response.headers["X-APISIX-Route"]
    assert hdr == "apisix-" + route_id, hdr

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
