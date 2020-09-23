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
    return p.stdout.read()

def getchildres(pid):
    for cpid in psutil.pids():
        if psutil.Process(int(cpid)).ppid()==int(pid):
            p = psutil.Process(int(cpid))
            print(cpid,p.memory_percent())
    
def cur_file_dir():
    return os.path.split(os.path.realpath(__file__))[0]

def geturl(url,times):
    start = time.time()
    tasks = []
    r = []
    while time.time() - start <= times:
        tasks.append(grequests.get(url))
        res = grequests.map(tasks, size=50)
        r.extend([i.status_code for i in res])
    return r

def setup_module():
    global headers,nginx_pid,apisixhost,apisixpid
    apisixpid = getpidbyname()
    apisixhost = "http://127.0.0.1:9080"
    headers = {"X-API-KEY": "edd1c9f034335f136f87ad84b625c8f1"}
    casepath = cur_file_dir()
    confpath = casepath + "/nginx.conf"
    p = subprocess.Popen(['openresty', '-p',casepath,'-c',confpath], stderr = subprocess.PIPE, stdout = subprocess.PIPE, shell = False) 
    p.wait()
    nginx_pid = p.pid+1

def teardown_module():
    pass
    #killprocesstree(nginx_pid)

def test_01():
    getchildres(apisixpid)
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
    r = geturl("%s/hello"%apisixhost,10)
    assert all(i == 200 for i in r)
    getchildres(apisixpid)

    r = requests.delete("%s/apisix/admin/routes/1"%apisixhost, headers=headers )
    r = requests.get("%s/hello"%apisixhost)
    assert r.status_code == 404
    r = geturl("%s/hello"%apisixhost,10)
    assert all(i == 404 for i in r)
    getchildres(apisixpid)

    print("the error log:\n")
    with open(cur_file_dir()+r"/logs/error.log") as fh:
        print(fh.read()) 
