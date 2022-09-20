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

# Usage:
# 1. pip3 install -r t/perf/requirements.txt --user
# 2. python3 ./t/perf/test_http.py
import http.client
import os
import shutil
import subprocess
import tempfile
import time
import unittest
import yaml


RULE_SIZE = 100


def create_conf():
    with open("./conf/config-perf.yaml", "w") as f:
        conf = {
            "apisix": {
                "enable_admin": False,
            },
            "deployment": {
                "role": "data_plane",
                "role_data_plane": {
                    "config_provider": "yaml",
                }

            },
            "nginx_config": {
                "worker_processes": 2
            }
        }
        yaml.dump(conf, f)

    routes = []
    consumers = []
    for i in range(RULE_SIZE):
        i = str(i)
        consumers.append({
            "username": "jack" + i,
            "plugins": {
                "jwt-auth": {
                    "key": "user-key-" + i,
                    "secret": "my-secret-key"
                }
            }
        })
        routes.append({
            "upstream_id": 1,
            "uri": "/*",
            "host": "test" + i + ".com",
            "plugins": {
                "limit-count": {
                    "count": 1e8,
                    "time_window": 3600,
                },
                "jwt-auth": {
                },
                "proxy-rewrite": {
                    "uri": "/" + i,
                    "headers": {
                        "X-APISIX-Route": "apisix-" + i
                    }
                },
                "response-rewrite": {
                    "headers": {
                        "X-APISIX-Route": "$http_x_apisix_route"
                    }
                },
            },
        })
    upstreams = [{
        "id": 1,
        "nodes": {
            "127.0.0.1:6666": 1
        },
        "type": "roundrobin"
    }]

    # expose public api
    routes.append({
        "uri": "/gen_token",
        "plugins": {
            "public-api": {
                "uri": "/apisix/plugin/jwt/sign"
            }
        },
    })

    conf = {}
    conf["routes"] = routes
    conf["consumers"] = consumers
    conf["upstreams"] = upstreams
    with open("./conf/apisix-perf.yaml", "w") as f:
        yaml.dump(conf, f)
        f.write("#END\n")

def apisix_executable():
    exe = "apisix"
    if os.path.exists("./bin/apisix"):
        exe = "./bin/apisix"
    return exe

def start_apisix():
    os.environ["APISIX_PROFILE"] = "perf"
    create_conf()
    subprocess.run([apisix_executable(), "start"])
    time.sleep(2)

def stop_apisix():
    subprocess.run([apisix_executable(), "stop"])

def start_upstream(wd):
    return subprocess.Popen(["nginx", "-p", wd])

def create_env():
    temp = tempfile.mkdtemp()
    print("Create test directory %s" % temp)
    shutil.copytree("t/perf/conf", os.path.join(temp, "conf"))
    os.mkdir(os.path.join(temp, "logs"))
    return temp


class TestHTTP(unittest.TestCase):

    def setUp(self):
        self.duration = os.environ.get("APISIX_PERF_DURATION", "300")
        self.n_client = os.environ.get("APISIX_PERF_CLIENT", "100")
        self.n_thread = os.environ.get("APISIX_PERF_THREAD", "2")
        self.qps = os.environ.get("APISIX_PERF_QPS", "8000")

        start_apisix()
        tempdir = create_env()
        self.upstream = start_upstream(tempdir)
        self.tempdir = tempdir

    def test_perf(self):
        signs = []
        conn = http.client.HTTPConnection("127.0.0.1", port=9080)
        for i in range(RULE_SIZE):
            i = str(i)
            conn.request("GET", "/gen_token?key=user-key-" + i)
            response = conn.getresponse()
            if response.status >= 300:
                print("failed to sign, got: %s" % response.read())
                conn.close()
                return
            signs.append('"' + response.read().decode() + '"')
        conn.close()

        script = os.path.join(self.tempdir, "wrk.lua")
        with open(script, "w") as f:
            sign_list = ",\n".join(signs)
            s = """
                signs = {%s}
                function request()
                    local i = math.random(%s) - 1
                    wrk.headers["Host"] = "test" .. i .. ".com"
                    wrk.headers["Authorization"] = signs[i+1]
                    return wrk.format()
                end
            """ % (sign_list, RULE_SIZE)
            f.write(s)
        # We use https://github.com/giltene/wrk2
        subprocess.run(["wrk",
            "-d", self.duration,
            "-c", self.n_client,
            "-t", self.n_thread,
            "-s", script,
            "-R", self.qps,
            "--u_latency", "http://127.0.0.1:9080/12345",
        ])

    def tearDown(self):
        stop_apisix()
        self.upstream.terminate()
        self.upstream.wait()


if __name__ == '__main__':
    unittest.main()
