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
    command = '''curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY:{key}" -X PUT -d '
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
