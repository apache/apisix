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
from boofuzz import *

def create_route():
    command = '''curl -i http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/post*",
    "methods": ["POST"],
    "plugins": {
        "serverless-post-function": {
            "functions": ["return function()\n local core = require(\"apisix.core\")\n   ngx.req.read_body()\n    local req_body = ngx.req.get_body_data()\n    if req_body == \"{\\\"a\\\":\\\"b\\\"}\"  then\n  return\n else\n  ngx.exit(ngx.HTTP_BAD_REQUEST)\n end\n end\n"]
        }
    },
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
        s_group("Method", ["GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "OPTIONS", "TRACE"])
        s_delim(" ", name="space-1")
        s_string("/post", name="Request-URI")
        s_delim(" ", name="space-2")
        s_string("HTTP/1.1", name="HTTP-Version")
        s_static("\r\n", name="Request-Line-CRLF")
        s_string("Host:", name="Host-Line")
        s_delim(" ", name="space-3")
        s_string("127.0.0.1:9080", name="Host-Line-Value")
        s_static("\r\n", name="Host-Line-CRLF")
        s_static('User-Agent', name='User-Agent-Header')
        s_delim(':', name='User-Agent-Colon-1')
        s_delim(' ', name='User-Agent-Space-1')
        s_string('Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3223.8 Safari/537.36', name='User-Agent-Value')
        s_static('\r\n', name='User-Agent-CRLF'),
        s_static('Accept', name='Accept-Header')
        s_delim(':', name='Accept-Colon-1')
        s_delim(' ', name='Accept-Space-1')
        s_string('text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8', name='Accept-Value')
        s_static('\r\n', name='Accept-CRLF')
        s_static("Content-Length:", name="Content-Length-Header")
        s_delim(" ", name="space-4")
        s_size("Body-Content", output_format="ascii", name="Content-Length-Value")
        s_static("\r\n", "Content-Length-CRLF")
        s_static('Connection', name='Connection-Header')
        s_delim(':', name='Connection-Colon-1')
        s_delim(' ', name='Connection-Space-1')
        s_group('Connection-Type', ['keep-alive', 'close'])
        s_static('\r\n', 'Connection-CRLF')
        s_static('Content-Type', name='Content-Type-Header')
        s_delim(':', name='Content-Type-Colon-1')
        s_delim(' ', name='Content-Type-Space-1')
        s_string('application/x-www-form-urlencoded', name='Content-Type-Value')
        s_static('\r\n', name='Content-Type-CRLF')
    s_static("\r\n", "Request-CRLF")

    with s_block("Body-Content"):
        s_string('{"a":"b"}', name="Body-Content-Value")

    session.connect(s_get("Request"))
    session.fuzz()

if __name__ == "__main__":
    run_test(create_route,run)
