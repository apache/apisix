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

import http.client
import subprocess
import time
import threading
from public import check_leak, run_test

def create_route():
    command = '''curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/client_abort",
    "upstream": {
        "nodes": {
            "127.0.0.1:6666": 1
        },
        "type": "roundrobin"
    }
}'
    '''
    subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)

def req():
    conn = http.client.HTTPConnection("127.0.0.1", port=9080)
    conn.request("GET", "/client_abort?seconds=0.01")
    time.sleep(0.001)
    conn.close()

def run_in_thread():
    for i in range(50):
        req()

@check_leak
def run():
    th = [threading.Thread(target=run_in_thread) for i in range(10)]
    for t in th:
        t.start()
    for t in th:
        t.join()


if __name__ == "__main__":
    run_test(create_route,run)
