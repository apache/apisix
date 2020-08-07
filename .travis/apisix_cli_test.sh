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

# 'make init' operates scripts and related configuration files in the current directory
# The 'apisix' command is a command in the /usr/local/apisix,
# and the configuration file for the operation is in the /usr/local/apisix/conf

set -ex

git checkout conf/config.yaml

# check whether the 'reuseport' is in nginx.conf .
make init

grep -E "listen 9080.*reuseport" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: nginx.conf file is missing reuseport configuration"
    exit 1
fi

echo "passed: nginx.conf file contains reuseport configuration"

# check default ssl port
sed  -i 's/listen_port: 9443/listen_port: 8443/g'  conf/config.yaml

make init

grep "listen 8443 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to update ssl port"
    exit 1
fi

grep "listen \[::\]:8443 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to update ssl port"
    exit 1
fi

echo "passed: change default ssl port"

# check nameserver imported

sed -i '/dns_resolver:/,+4s/^/#/'  conf/config.yaml

make init

i=`grep  -E '^nameserver[[:space:]]+(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4]0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])[[:space:]]?$' /etc/resolv.conf | awk '{print $2}'`
for ip in $i
do
  echo $ip
  grep $ip conf/nginx.conf > /dev/null
  if [ ! $? -eq 0 ]; then
    echo "failed: system DNS "$ip" unimported"
    exit 1
  fi
done

sed -i '/dns_resolver:/,+4s/^#//'  conf/config.yaml
echo "passed: system nameserver imported"

# enable enable_dev_mode
sed  -i 's/enable_dev_mode: false/enable_dev_mode: true/g'  conf/config.yaml

make init

count=`grep -c "worker_processes 1;" conf/nginx.conf`
if [ $count -ne 1 ]; then
    echo "failed: worker_processes is not 1 when enable enable_dev_mode"
    exit 1
fi

count=`grep -c "listen 9080.*reuseport" conf/nginx.conf || true`
if [ $count -ne 0 ]; then
    echo "failed: reuseport should be disabled when enable enable_dev_mode"
    exit 1
fi

git checkout conf/config.yaml

# check whether the 'worker_cpu_affinity' is in nginx.conf .

make init

grep -E "worker_cpu_affinity" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: nginx.conf file is missing worker_cpu_affinity configuration"
    exit 1
fi

echo "passed: nginx.conf file contains worker_cpu_affinity configuration"

# check admin https enabled

sed  -i 's/\# port_admin: 9180/port_admin: 9180/'  conf/config.yaml
sed  -i 's/\# https_admin: true/https_admin: true/'  conf/config.yaml

make init

grep "listen 9180 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: failed to enabled https for admin"
    exit 1
fi

make run

code=$(curl -k -i -m 20 -o /dev/null -s -w %{http_code} https://127.0.0.1:9180/apisix/admin/routes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1')
if [ ! $code -eq 200 ]; then
    echo "failed: failed to enabled https for admin"
    exit 1
fi

echo "passed: admin https enabled"

# rollback to the default

make stop

sed  -i 's/port_admin: 9180/\# port_admin: 9180/'  conf/config.yaml
sed  -i 's/https_admin: true/\# https_admin: true/'  conf/config.yaml

make init

set +ex

grep "listen 9180 ssl" conf/nginx.conf > /dev/null
if [ ! $? -eq 1 ]; then
    echo "failed: failed to rollback to the default admin config"
    exit 1
fi

set -ex

echo "passed: rollback to the default admin config"

# check the 'worker_shutdown_timeout' in 'nginx.conf' .

make init

grep -E "worker_shutdown_timeout 240s" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: worker_shutdown_timeout in nginx.conf is required 240s"
    exit 1
fi

echo "passed: worker_shutdown_timeout in nginx.conf is ok"

# check worker processes number is configurable.

sed -i 's/worker_processes: auto/worker_processes: 2/'  conf/config.yaml

make init

grep "worker_processes 2;" conf/nginx.conf > /dev/null
if [ ! $? -eq 0 ]; then
    echo "failed: worker_processes in nginx.conf doesn't change"
    exit 1
fi

sed -i 's/worker_processes: 2/worker_processes: auto/'  conf/config.yaml
echo "passed: worker_processes number is configurable"
