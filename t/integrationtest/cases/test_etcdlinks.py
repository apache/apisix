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
import sys,os,time,json,subprocess,signal
import requests,psutil,grequests

def kill_processtree(id):
    for pid in psutil.pids():
        if psutil.Process(int(pid)).ppid()==id:
            psutil.Process(int(pid)).terminate()
    psutil.Process(id).terminate()

def get_pid_byname():
    name = "apisix"
    cmd = "ps -ef | grep %s | grep nginx | grep -v grep | grep -v %s/t | awk '{print $2}'"%(name,name)
    p = subprocess.Popen(cmd, stderr = subprocess.PIPE, stdout = subprocess.PIPE, shell = True)
    p.wait()
    return p.stdout.read().strip()

def get_workernum(pid):
    parent = psutil.Process(pid)
    children = parent.children(recursive=True)
    return len(children)

def get_etcdlinks():
    for r in psutil.process_iter():
        if r.name()=="etcd":
            return len(psutil.Process(r.pid).connections())

def cur_file_dir():
    return os.path.split(os.path.realpath(__file__))[0]

def setup_module():
    global headers,nginx_pid,apisixhost,apisixpid,apisixpath
    apisixpid = int(getpidbyname())
    apisixpath = psutil.Process(apisixpid).cwd()
    apisixhost = "http://127.0.0.1:9080"
    headers = {"X-API-KEY": "edd1c9f034335f136f87ad84b625c8f1"}
    casepath = cur_file_dir()

def teardown_module():
    pass

def test_etcdlinks01():
    time.sleep(30)
    assert getetcdlinks() <= getworkernum(apisixpid)*7
