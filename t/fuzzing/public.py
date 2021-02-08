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

#! /usr/bin/env python
import subprocess
import os
import psutil

def cur_dir():
    return os.path.split(os.path.realpath(__file__))[0]

def check_log(*logs):
    boofuzz_log = logs[0]
    apisix_errorlog = logs[1]
    apisix_accesslog = logs[2]

    cmds = ['cat %s | grep -a "fail"'%boofuzz_log, 'cat %s | grep -a "error"'%apisix_errorlog, 'cat %s | grep -a " 500 "'%apisix_accesslog]
    for cmd in cmds:
        r = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE).stdout.read()
        assert r == ""

def check_process():
    cmd = "ps -ef | grep fuzzing/upstream/nginx.conf | grep master | grep -v grep| awk '{print $2}'"
    p = subprocess.Popen(cmd, stderr = subprocess.PIPE, stdout = subprocess.PIPE, shell = True)
    p.wait()
    parent = psutil.Process(int(p.stdout.read().strip()))
    children = parent.children(recursive=True)
    process = {p.pid for p in children}
    process.add(parent.pid)
    return process
