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

install_brotli() {
    apt-get -qy update
    apt-get install -y --no-install-recommends brotli libbrotli1
    link_brotli_sonames
}

# brotli-ffi calls ffi.load("brotlienc"), which resolves the unversioned
# soname. The distro ships that symlink in libbrotli-dev, so create it here
# instead of pulling build headers into the runtime image.
link_brotli_sonames() {
    local lib so dir
    for lib in brotlicommon brotlidec brotlienc; do
        so=$(ldconfig -p | awk -v n="lib${lib}.so.1" '$1 == n { print $NF; exit }')
        if [ -z "${so}" ]; then
            echo "lib${lib}.so.1 not found after install" >&2
            exit 1
        fi
        dir=$(dirname "${so}")
        ln -sf "lib${lib}.so.1" "${dir}/lib${lib}.so"
    done
    ldconfig
}

install_brotli
