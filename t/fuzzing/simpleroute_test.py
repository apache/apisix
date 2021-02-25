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
from public import *
from boofuzz import *

def create_route():
    command = '''curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get*",
    "methods": ["GET"],
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:6666": 1
        }
    }
}'
    '''
    subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)

def main():
    fw = open(cur_dir() + "/test.log",'wb')
    fuzz_loggers = [FuzzLoggerText(file_handle=fw)]
    session = Session(
        target=Target(
            connection=TCPSocketConnection("127.0.0.1", 9080, send_timeout=5.0, recv_timeout=5.0, server=False)
        ),
        fuzz_loggers=fuzz_loggers,
        keep_web_open=False,
    )

    s_initialize(name="Request")
    with s_block("Request-Line"):
        s_group("Method", ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'CONNECT', 'OPTIONS', 'TRACE'])
        s_delim(" ", name='space-1')
        s_string("/get", name='Request-URI')
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

    s_static("\r\n", "Request-CRLF")
    session.connect(s_get("Request"))
    session.fuzz()

if __name__ == "__main__":
    # before test
    create_route()
    r1 = check_process()
    main()
    # after test
    boofuzz_log = cur_dir() + "/test.log"
    apisix_errorlog = "~/work/apisix/apisix/logs/error.log"
    apisix_accesslog = "~/work/apisix/apisix/logs/access.log"
    check_log(boofuzz_log, apisix_errorlog, apisix_accesslog)
    r2 = check_process()
    if r2 != r1:
        print("before test, nginx's process list:%s,\nafter test, nginx's process list:%s"%(r1,r2))
        raise AssertionError
