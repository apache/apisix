#!/usr/bin/env bash
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

# GitHub Action CI runner comes with a limited disk space, due to several reasons
# it may become full. For example, caching docker images creates an archive of
# several GBs of size, this sometimes leads to disk usage becoming full.
# To keep CI functional, we delete large directories that we do not need.

echo "=============================================================================="
echo "Freeing up disk space on CI system"
echo "=============================================================================="

df -h
echo "Removing unnecessary large directories"
sudo rm -rf /usr/local/lib/android /usr/share/dotnet /usr/share/swift
df -h
