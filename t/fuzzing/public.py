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
import os
from functools import wraps
from pathlib import Path
import psutil
from boofuzz import FuzzLoggerText, Session, TCPSocketConnection, Target

def cur_dir():
    return os.path.split(os.path.realpath(__file__))[0]

def apisix_pwd():
    return os.environ.get("APISIX_FUZZING_PWD") or \
            (str(Path.home()) + "/work/apisix/apisix")

def connect_admin():
    conn = http.client.HTTPConnection("127.0.0.1", port=9180)
    return conn

def check_log():
    boofuzz_log = cur_dir() + "/test.log"
    apisix_errorlog = apisix_pwd() + "/logs/error.log"
    apisix_accesslog = apisix_pwd() + "/logs/access.log"

    cmds = ['cat %s | grep -a "error" | grep -v "invalid request body"'%apisix_errorlog, 'cat %s | grep -a " 500 "'%apisix_accesslog]
    if os.path.exists(boofuzz_log):
        cmds.append('cat %s | grep -a "fail"'%boofuzz_log)
    for cmd in cmds:
        r = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
        err = r.stdout.read().strip()
        print("Error in log: ", err)
        assert err == b""

def check_process():
    with open(apisix_pwd() + "/logs/nginx.pid") as f:
        pid = int(f.read().strip())
    parent = psutil.Process(pid)
    children = parent.children(recursive=True)
    process = {p.pid for p in children if "cache loader process" not in p.cmdline()[0]}
    process.add(parent.pid)
    return process

def initfuzz():
    fw = open(cur_dir() + "/test.log",'w')
    fuzz_loggers = [FuzzLoggerText(file_handle=fw)]
    session = Session(
        target=Target(
            connection=TCPSocketConnection("127.0.0.1", 9080, send_timeout=5.0, recv_timeout=5.0, server=False)
        ),
        fuzz_loggers=fuzz_loggers,
        keep_web_open=False,
    )
    return session

def sum_memory():
    pmap = {}
    for p in check_process():
        proc = psutil.Process(p)
        pmap[proc] = proc.memory_full_info()
    return sum(m.rss for m in pmap.values())

def get_linear_regression_sloped(samples):
    n = len(samples)
    avg_x = (n + 1) / 2
    avg_y = sum(samples) / n
    avg_xy = sum([(i + 1) * v for i, v in enumerate(samples)]) / n
    avg_x2 = sum([i * i for i in range(1, n + 1)]) / n
    denom = avg_x2 - avg_x * avg_x
    if denom == 0:
        return None
    return (avg_xy - avg_x * avg_y) / denom

def gc():
    conn = http.client.HTTPConnection("127.0.0.1", port=9090)
    conn.request("POST", "/v1/gc")
    conn.close()

def leak_count():
    return int(os.environ.get("APISIX_FUZZING_LEAK_COUNT") or 100)

LEAK_COUNT = leak_count()

def check_leak(f):
    @wraps(f)
    def wrapper(*args, **kwds):
        global LEAK_COUNT

        samples = []
        for i in range(LEAK_COUNT):
            f(*args, **kwds)
            gc()
            samples.append(sum_memory())
        count = 0
        for i in range(1, LEAK_COUNT):
            if samples[i - 1] < samples[i]:
                count += 1
        print(samples)
        sloped = get_linear_regression_sloped(samples)
        print(sloped)
        print(count / LEAK_COUNT)

        if os.environ.get("CI"): # CI is not stable
            return

        # the threshold is chosen so that we can find leaking a table per request
        if sloped > 10000 and (count / LEAK_COUNT) > 0.2:
            raise AssertionError("memory leak")

    return wrapper

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
