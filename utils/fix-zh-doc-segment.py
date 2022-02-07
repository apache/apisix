#!/usr/bin/env python3
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
import os
from os import path
from zhon.hanzi import punctuation # sudo pip3 install zhon


def need_fold(pre, cur):
    pre = pre.rstrip("\r\n")
    if len(pre) == 0 or len(cur) == 0:
        return False
    if ord(pre[-1]) < 128 or ord(cur[0]) < 128:
        return False
    # the prev line ends with Chinese and the curr line starts with Chinese
    if pre.startswith(":::note"):
        # ignore special mark
        return False
    if pre[-1] in punctuation:
        # skip punctuation
        return False
    return True

def check_segment(root):
    for parent, dirs, files in os.walk(root):
        for fn in files:
            fn = path.join(parent, fn)
            with open(fn) as f:
                lines = f.readlines()
                new_lines = [lines[0]]
                skip = False
                for i in range(1, len(lines)):
                    if lines[i-1].startswith('```'):
                        skip = not skip
                    if not skip and need_fold(lines[i-1], lines[i]):
                        new_lines[-1] = new_lines[-1].rstrip("\r\n") + lines[i]
                    else:
                        new_lines.append(lines[i])
            if len(new_lines) != len(lines):
                print("find broken newline in file: %s" % fn)
                with open(fn, "w") as f:
                    f.writelines(new_lines)


roots = ["docs/zh/latest/"]
for r in roots:
    check_segment(r)
