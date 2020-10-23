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

# !/usr/bin/env python
# -*- coding: utf-8 -*-

import random
import subprocess
import shutil
import time
import datetime
import sys
import os
import json
import re
import base64
from sys import version_info


def cur_file_dir():
    return os.path.split(os.path.realpath(__file__))[0]


def env_prepare(casedirpath):
    updatepip = "curl https://bootstrap.pypa.io/get-pip.py | python"
    if version_info.major == 2:
        requirements = "python -m pip install -r %s/requirements.txt" %\
                     cur_file_dir()
    else:
        requirements = "python3 -m pip install -r %s/requirements.txt" %\
                     cur_file_dir()
    r_exc_case_cmd = subprocess.Popen(updatepip, stderr=subprocess.PIPE,
                                      shell=True)
    r_exc_case_cmd.wait()
    err = r_exc_case_cmd.stderr.read()

    r_exc_case_cmd = subprocess.Popen(requirements, stderr=subprocess.PIPE,
                                      shell=True)
    r_exc_case_cmd.wait()
    err = r_exc_case_cmd.stderr.read()

casepath = cur_file_dir()+"/cases"
env_prepare(casepath)
