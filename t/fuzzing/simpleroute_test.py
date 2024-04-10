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
import yaml


def get_admin_key_from_yaml(yaml_file_path):
    with open(yaml_file_path, 'r') as file:
        yaml_data = yaml.safe_load(file)
    try:
        admin_key = yaml_data['deployment']['admin']['admin_key'][0]['key']
        return admin_key
    except KeyError:
        return None




def create_route():
    key = get_admin_key_from_yaml('conf/config.yaml')
    if key is None:
        print("Key not found in the YAML file.")
        return
    # Construct curl command with the extracted key
    command = f'''curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: {key}" -X PUT -d '
{{
    "uri": "/get*",
    "methods": ["GET"],
    "upstream": {{
        "type": "roundrobin",
        "nodes": {{
            "127.0.0.1:6666": 1
        }}
    }}
}}'
    '''
    subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)

def run():
    session = initfuzz()

    s_initialize(name="Request")
    with s_block("Request-Line"):
        s_group("Method", ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'CONNECT', 'OPTIONS', 'TRACE', "PURGE"])
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
    session.fuzz(max_depth=1)

if __name__ == "__main__":
    run_test(create_route,run)
