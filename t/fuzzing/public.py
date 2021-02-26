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
import os
import psutil
from boofuzz import *

def cur_dir():
    return os.path.split(os.path.realpath(__file__))[0]

def check_log():
    boofuzz_log = cur_dir() + "/test.log"
    apisix_errorlog = "~/work/apisix/apisix/logs/error.log"
    apisix_accesslog = "~/work/apisix/apisix/logs/access.log"

    cmds = ['cat %s | grep -a "fail"'%boofuzz_log, 'cat %s | grep -a "error" | grep -v "invalid request body"'%apisix_errorlog, 'cat %s | grep -a " 500 "'%apisix_accesslog]
    for cmd in cmds:
        r = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
        assert r.stdout.read().strip() == ""

def check_process():
    cmd = "ps -ef | grep apisix/conf/nginx.conf | grep master | grep -v grep| awk '{print $2}'"
    p = subprocess.Popen(cmd, stderr = subprocess.PIPE, stdout = subprocess.PIPE, shell = True)
    p.wait()
    parent = psutil.Process(int(p.stdout.read().strip()))
    children = parent.children(recursive=True)
    process = {p.pid for p in children if "cache loader process" not in p.cmdline()[0]}
    process.add(parent.pid)
    return process

def initfuzz():
    fw = open(cur_dir() + "/test.log",'wb')
    fuzz_loggers = [FuzzLoggerText(file_handle=fw)]
    session = Session(
        target=Target(
            connection=TCPSocketConnection("127.0.0.1", 9080, send_timeout=5.0, recv_timeout=5.0, server=False)
        ),
        fuzz_loggers=fuzz_loggers,
        keep_web_open=False,
    )
    return session

def run_test(create_route, run):
    # before test
    create_route()
    r1 = check_process()
    run()
    # after test
    check_log()
    r2 = check_process()
    if r2 != r1:
        print("before test, nginx's process list:%s,\nafter test, nginx's process list:%s"%(r1,r2))
        raise AssertionError
