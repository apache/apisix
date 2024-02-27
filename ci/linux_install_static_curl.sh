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

set -ex

install_static_curl () {
    CURL_VERSION="8.6.0"
    wget -q https://github.com/stunnel/static-curl/releases/download/${CURL_VERSION}/curl-linux-amd64-${CURL_VERSION}.tar.xz
    tar -xf curl-linux-amd64-${CURL_VERSION}.tar.xz
    sudo apt remove -y curl
    sudo cp curl /usr/bin
    curl -V
}

install_static_curl
