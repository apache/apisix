#!/usr/bin/env python
# coding: utf-8
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
import sys
# sudo pip install requests
import requests

# Usage: ./create-ssl.py t.crt t.key test.com
if len(sys.argv) <= 3:
    print("bad argument")
    sys.exit(1)
with open(sys.argv[1]) as f:
    cert = f.read()
with open(sys.argv[2]) as f:
    key = f.read()
sni = sys.argv[3]
api_key = "edd1c9f034335f136f87ad84b625c8f1"
resp = requests.put("http://127.0.0.1:9080/apisix/admin/ssl/1", json={
    "cert": cert,
    "key": key,
    "snis": [sni],
}, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
