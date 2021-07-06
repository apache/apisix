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

import subprocess
from public import initfuzz, run_test
from boofuzz import s_block, s_delim, s_get, s_group, s_initialize, s_static, s_string

def create_route():
    command = '''curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/parameter*",
    "vars": [
        ["arg_name","==","jack"],
        ["http_token","==","140b543013d988f4767277b6f45ba542"]
    ],
    "upstream": {
        "nodes": {
            "127.0.0.1:6666": 1
        },
        "type": "roundrobin"
    }
}'
    '''
    subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)

def run():
    session = initfuzz()

    s_initialize(name="Request")
    with s_block("Request-Line"):
        s_group("Method", ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'CONNECT', 'OPTIONS', 'TRACE'])
        s_delim(" ", name='space-1')
        s_string("/parameter?name=jack", name='Request-URI')
        s_delim(" ", name='space-2')
        s_string('HTTP/1.1', name='HTTP-Version')
        s_static("\r\n", name="Request-Line-CRLF")
        s_string("Host:", name="Host-Line")
        s_delim(" ", name="space-3")
        s_string("example.com", name="Host-Line-Value")
        s_static("\r\n", name="Host-Line-CRLF")
        s_string("Connection:", name="Connection-Line")
        s_delim(" ", name="space-4")
        s_string("Keep-Alive", name="Connection-Line-Value")
        s_static("\r\n", name="Connection-Line-CRLF")
        s_string("User-Agent:", name="User-Agent-Line")
        s_delim(" ", name="space-5")
        s_string("Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.1 (KHTML, like Gecko) Chrome/21.0.1180.83 Safari/537.1", name="User-Agent-Line-Value")
        s_static("\r\n", name="User-Agent-Line-CRLF")
        s_string("token:", name="age-Line")
        s_delim(" ", name="space-6")
        s_string("140b543013d988f4767277b6f45ba542", name="age-Line-Value")
        s_static("\r\n", name="age-Line-CRLF")

    s_static("\r\n", "Request-CRLF")
    session.connect(s_get("Request"))
    session.fuzz()

if __name__ == "__main__":
    run_test(create_route,run)
