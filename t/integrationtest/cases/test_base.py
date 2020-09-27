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

#!/usr/bin/env python
#-*- coding: utf-8 -*-
import sys,os,time,requests,json,subprocess,signal,psutil,grequests

def killprocesstree(id):
    for pid in psutil.pids():
        if psutil.Process(int(pid)).ppid()==id:
            psutil.Process(int(pid)).terminate()
    psutil.Process(id).terminate()

def getpidbyname():
    name = "apisix"
    cmd = "ps -ef | grep %s | grep nginx | grep -v grep | grep -v %s/t | awk '{print $2}'"%(name,name)
    p = subprocess.Popen(cmd, stderr = subprocess.PIPE, stdout = subprocess.PIPE, shell = True)
    p.wait()
    return p.stdout.read().strip()

def getworkerres(pid):
    for cpid in psutil.pids():
        if psutil.Process(int(cpid)).ppid()==int(pid):
            p = psutil.Process(int(cpid))
            print(cpid,p.cpu_percent(interval=1.0),p.memory_percent())

def cur_file_dir():
    return os.path.split(os.path.realpath(__file__))[0]

def requesttest(url,times):
    start = time.time()
    tasks = []
    r = []
    while time.time() - start <= times:
        tasks.append(grequests.get(url))
        res = grequests.map(tasks, size=50)
        r.extend([i.status_code for i in res])
    return r

def setup_module():
    global headers,nginx_pid,apisixhost,apisixpid,apisixpath
    apisixpid = int(getpidbyname())
    apisixpath = psutil.Process(apisixpid).cwd()
    apisixhost = "http://127.0.0.1:9080"
    headers = {"X-API-KEY": "edd1c9f034335f136f87ad84b625c8f1"}
    casepath = cur_file_dir()
    confpath = casepath + "/nginx.conf"
    try:
        os.makedirs("./cases/logs")
    except Exception as e:
        pass
    p = subprocess.Popen(['openresty', '-p',casepath,'-c',confpath], stderr = subprocess.PIPE, stdout = subprocess.PIPE, shell = False)
    p.wait()
    nginx_pid = p.pid+1

def teardown_module():
    pass
    # killprocesstree(nginx_pid)

def test_basescenario01():
    print("APISIX's resource occupation(before test):")
    getworkerres(apisixpid)
    cfgdata = {
    "uri": "/hello",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:9666": 1
        }
    }
}
    r = requests.put("%s/apisix/admin/routes/1"%apisixhost, json=cfgdata,headers=headers )
    r = json.loads(r.content)
    assert r["action"] == "set"
    r = requests.get("%s/hello"%apisixhost)
    assert r.status_code == 200 and "Hello, World!" in r.content
    r = requesttest("%s/hello"%apisixhost,10)
    assert all(i == 200 for i in r)
    print("APISIX's resource occupation(after set route and request test):")
    getworkerres(apisixpid)

    r = requests.delete("%s/apisix/admin/routes/1"%apisixhost, headers=headers )
    r = requests.get("%s/hello"%apisixhost)
    assert r.status_code == 404
    r = requesttest("%s/hello"%apisixhost,10)
    assert all(i == 404 for i in r)
    print("APISIX's resource occupation(after delete route and request test):")
    getworkerres(apisixpid)

    print("APISIX's error log:")
    with open(apisixpath+r"/logs/error.log") as fh:
        print(fh.read())
