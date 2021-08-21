#!/usr/bin/env python
# coding: utf-8
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
import json
import os
import sys
from os import path

EXT = ".md"

try:
    UNICODE_EXISTS = bool(type(unicode))
except:
    # Py2
    unicode = str

def collect_fn(entries, topic):
    if "id" in topic:
        fn = topic["id"]
        entries.append(fn)
    elif "items" in topic:
        for item in topic["items"]:
            if isinstance(item, unicode):
                entries.append(item)
            else:
                collect_fn(entries, item)

def check_category(root):
    index = root + "config.json"
    with open(index) as f:
        entries = []

        data = json.load(f)
        for topic in data["sidebar"]:
            collect_fn(entries, topic)
        for e in entries:
            fn = root + e + EXT
            if not path.exists(fn):
                print("Entry %s in the sidebar can't be found. Please remove it from %s."
                        % (fn, index))
                return False

        ignore_list = ["examples/plugins-hmac-auth-generate-signature", "config", "README"]
        entries.extend(ignore_list)
        existed_files = []
        for parent, dirs, files in os.walk(root):
            for fn in files:
                existed_files.append(path.join(parent[len(root):], path.splitext(fn)[0]))
        for fn in existed_files:
            if fn not in entries:
                print("File %s%s%s is not indexed. Please add it to %s." % (root, fn, EXT, index))
                return False
        return True

roots = ["docs/en/latest/", "docs/zh/latest/"]
for r in roots:
    if not check_category(r):
        sys.exit(-1)
