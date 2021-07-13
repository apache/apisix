---
title: How to build Apache APISIX
---

<!--
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
-->

## 1. Install dependencies

The runtime environment for Apache APISIX requires Nginx and etcd.

So before installation, please follow the different operating systems [install Dependencies](install-dependencies.md).

The Docker / Helm Chart installation may already contain the required Nginx or etcd.
Please refer to their own documentations.

## 2. Install Apache APISIX

You can install Apache APISIX in a variety of ways, including source code packages, Docker, and Helm Chart.

### Installation via RPM package (CentOS 7)

```shell
sudo yum install -y https://github.com/apache/apisix/releases/download/2.7/apisix-2.7-0.x86_64.rpm
```

### Installation via Docker

See https://hub.docker.com/r/apache/apisix

### Installation via Helm Chart

See https://github.com/apache/apisix-helm-chart

### Installation via source release

You need to download the Apache source release first:

```shell
$ mkdir apisix-2.7
$ wget https://downloads.apache.org/apisix/2.7/apache-apisix-2.7-src.tgz
$ tar zxvf apache-apisix-2.7-src.tgz -C apisix-2.7
```

Install the Lua libraries that the runtime depends on:

```shell
cd apisix-2.7
make deps
```

## 3. Manage (start/stop) APISIX Server

We can start the APISIX server by command `make run` in APISIX home folder,
or we can stop APISIX server by command `make stop`.

```shell
# init nginx config file and etcd
$ make init

# start APISIX server
$ make run

# stop APISIX server gracefully
$ make quit

# stop APISIX server immediately
$ make stop

# more actions find by `help`
$ make help
```

Environment variable can be used to configure APISIX. Please take a look at `conf/config.yaml` to
see how to do it.

## 4. Test

1. Install perl's package manager `cpanminus` first
2. Then install `test-nginx`'s dependencies via `cpanm`:：`sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)`
3. Clone source code：`git clone https://github.com/iresty/test-nginx.git`. Note that we should use our fork.
4. Load the `test-nginx` library with perl's `prove` command and run the test cases in the `/t` directory:
    * Set PERL5LIB for perl module: `export PERL5LIB=.:$PERL5LIB`
    * Run the test cases: `make test`
    * To set the path of nginx to run the test cases: `TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`
    * Some tests depend on external services and modified system configuration. If you want to setup a local CI environment,
      you can refer to `ci/linux_openresty_common_runner.sh`.

### Troubleshoot Testing

**Set Nginx Path**

- If you run in to an issue `Error unknown directive "lua_package_path" in /API_ASPIX/apisix/t/servroot/conf/nginx.conf`
make sure to set openresty as default nginx. And export the path as below.

* export PATH=/usr/local/openresty/nginx/sbin:$PATH
    - Linux default installation path:
        * export PATH=/usr/local/openresty/nginx/sbin:$PATH
    - OSx default installation path via homebrew:
        * export PATH=/usr/local/opt/openresty/nginx/sbin:$PATH

**Run Individual Test Cases**

- Use the following command to run test cases constrained to a file:
    - prove -Itest-nginx/lib -r t/plugin/openid-connect.t

## 5. Update Admin API token to protect Apache APISIX

Changes the `apisix.admin_key` in the file `conf/config.yaml` and restart the service.
Here is an example:

```yaml
apisix:
  # ... ...
  admin_key
    -
      name: "admin"
      key: abcdefghabcdefgh
      role: admin
```

When calling the Admin API, `key` can be used as a token.

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes?api_key=abcdefghabcdefgh -i
HTTP/1.1 200 OK
Date: Fri, 28 Feb 2020 07:48:04 GMT
Content-Type: text/plain
... ...
{"node":{...},"action":"get"}

$ curl http://127.0.0.1:9080/apisix/admin/routes?api_key=abcdefghabcdefgh-invalid -i
HTTP/1.1 401 Unauthorized
Date: Fri, 28 Feb 2020 08:17:58 GMT
Content-Type: text/html
... ...
{"node":{...},"action":"get"}
```

## 6. Build OpenResty for APISIX

Some features require you to build OpenResty with extra Nginx modules.
If you need those features, you can build OpenResty with
[this build script](https://raw.githubusercontent.com/api7/apisix-build-tools/master/build-apisix-openresty.sh).

## 7. Add systemd unit file for APISIX

If you install APISIX with rpm package, the unit file is installed automatically, and you could directly do

```
$ systemctl start apisix
$ systemctl stop apisix
$ systemctl enable apisix
```

If installed in other methods, you could refer to [the unit file template](https://github.com/api7/apisix-build-tools/blob/master/usr/lib/systemd/system/apisix.service), modify if needed, and place it as `/usr/lib/systemd/system/apisix.service`.
