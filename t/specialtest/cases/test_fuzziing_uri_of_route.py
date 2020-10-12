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
import sys,os,time,json,subprocess,signal,random
import requests,psutil,grequests,string,urllib

def kill_processtree(id):
    parent = psutil.Process(pid)
    children = parent.children(recursive=True)
    for p in children:
        psutil.Process(p.pid).terminate()
    psutil.Process(id).terminate()

def get_pid_byname():
    name = "apisix"
    cmd = "ps -ef | grep %s/conf | grep master | grep -v grep| awk '{print $2}'"%name
    p = subprocess.Popen(cmd, stderr = subprocess.PIPE, stdout = subprocess.PIPE, shell = True)
    p.wait()
    return p.stdout.read().strip()

def get_workerres(pid):
    parent = psutil.Process(pid)
    children = parent.children(recursive=True)
    for p in children:
        cp = psutil.Process(p.pid)
        print(p.pid,cp.cpu_percent(interval=1.0),cp.memory_percent())

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
    global headers,apisixhost,apisixpid,apisixpath
    apisixpid = int(get_pid_byname())
    apisixpath = psutil.Process(apisixpid).cwd()
    os.chdir(apisixpath)
    subprocess.Popen("> logs/error.log",shell = True, stdout = subprocess.PIPE)
    apisixpid = int(get_pid_byname())
    print("=============APISIX's pid:",apisixpid)
    apisixhost = "http://127.0.0.1:9080"
    headers = {"X-API-KEY": "edd1c9f034335f136f87ad84b625c8f1"}
    confpath = "./t/specialtest/cases/nginx.conf"
    try:
        os.makedirs("./t/specialtest/cases/logs")
    except Exception as e:
        pass
    p = subprocess.Popen(['openresty', '-p', apisixpath ,'-c',confpath], stderr = subprocess.PIPE, stdout = subprocess.PIPE, shell = False)
    p.wait()

def teardown_module():
    pass

def test_fuzzing_uri_of_route():
    print("====APISIX's resource occupation(before test):")
    get_workerres(apisixpid)
    #use environment variables "FUZZING_URI" you can setting the numbers of test uris
    fuzzing_uri_nums = 1000 if not os.getenv('FUZZING_URI') else os.getenv('FUZZING_URI')
    orgin_char = '''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/'''

    for i in range(int(fuzzing_uri_nums)):
        length = random.randint(1, 4080)
        tmpuri = "".join(random.sample(list(orgin_char)*(length//len(orgin_char) + 1),length)).replace("//","/")
        uri = "/hello%s"%tmpuri
        assert len("/hello%s"%uri)<=4096
        cfgdata = {
        "uri": uri,
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:9666": 1
            }
        }
    }

        r = requests.put("%s/apisix/admin/routes/1"%apisixhost, json=cfgdata,headers=headers )
        assert r.status_code == 200
        time.sleep(0.1)
        #verify route
        r = requests.get("%s%s"%(apisixhost,uri))
        if r.status_code != 200 or "Hello, World!" not in r.content :
            print(uri,r.status_code, r.content)
            raise AssertionError('assertError')

    print("====APISIX's resource occupation(after set route and request test):")
    get_workerres(apisixpid)
    print("====APISIX's error log:")
    with open(apisixpath+r"/logs/error.log") as fh:
        print(fh.read())
