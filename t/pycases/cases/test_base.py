#!/usr/bin/env python
#-*- coding: utf-8 -*-
import sys,os,time,requests,json

def setup_module():
    global headers
    headers = {"X-API-KEY": "edd1c9f034335f136f87ad84b625c8f1"}
    print("setup_module")

def teardown_module():
    print("teardown_module")


def test_01(): 
	cfgdata = {
    "uri": "/apisix/status",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}
	r = requests.put("http://127.0.0.1:9080/apisix/admin/routes/1", json=cfgdata,headers=headers )
	r = json.loads(r.content)
	assert r["action"] == "set"

	r = requests.get("http://127.0.0.1:9080/apisix/admin/routes/1", headers=headers )
	r = json.loads(r.content)
	assert r["action"] == "set"

	r = requests.get("http://127.0.0.1:9080/apisix/status")
	assert r.status_code == 200