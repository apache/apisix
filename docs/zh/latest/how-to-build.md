---
title: 如何构建 Apache APISIX
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

## 1. 安装依赖

Apache APISIX 的运行环境需要 Nginx 和 etcd，

所以在安装前，请根据不同的操作系统来[安装依赖](install-dependencies.md)。

通过 Docker / Helm Chart 安装时可能已经包含了所需的 Nginx 和 etcd。
请参照各自对应的文档。

## 2. 安装 Apache APISIX

你可以通过源码包、Docker、Helm Chart 等多种方式来安装 Apache APISIX。

### 通过 RPM 包安装（CentOS 7）

```shell
sudo yum install -y https://github.com/apache/apisix/releases/download/2.7/apisix-2.7-0.x86_64.rpm
```

### 通过 Docker 安装

见 https://hub.docker.com/r/apache/apisix

### 通过 Helm Chart 安装

见 https://github.com/apache/apisix-helm-chart

### 通过源码包安装

你需要先下载 Apache Release 源码包：

```shell
$ mkdir apisix-2.7
$ wget https://downloads.apache.org/apisix/2.7/apache-apisix-2.7-src.tgz
$ tar zxvf apache-apisix-2.7-src.tgz -C apisix-2.7
```

安装运行时依赖的 Lua 库：

```
cd apisix-2.7
make deps
```

## 3. 管理（启动、关闭等）APISIX 服务

我们可以在 apisix 的目录下用 `make run` 命令来启动服务，或者用 `make stop` 方式关闭服务。

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

## 4. 运行测试案例

1. 先安装 perl 的包管理器 cpanminus
2. 然后通过 cpanm 来安装 test-nginx 的依赖：`sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)`
3. 然后 clone 最新的源码：`git clone https://github.com/iresty/test-nginx.git`。注意使用我们 fork 出来的版本。
4. 通过 perl 的 `prove` 命令来加载 test-nginx 的库，并运行 `/t` 目录下的测试案例集：
    * 追加当前目录到perl模块目录： `export PERL5LIB=.:$PERL5LIB`
    * 直接运行：`make test`
    * 指定 nginx 二进制路径：`TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`
    * 部分测试需要依赖外部服务和修改系统配置。如果想要完整地构建测试环境，可以参考 `ci/linux_openresty_common_runner.sh`。

### 疑难排解测试

**配置 Nginx 路径**

如果遇到问题 `Error unknown directive "lua_package_path" in /API_ASPIX/apisix/t/servroot/conf/nginx.conf`
确保将openresty设置为默认的nginx并按如下所示导出路径。

* export PATH=/usr/local/openresty/nginx/sbin:$PATH
  * Linux 默认安装路径：
    * export PATH=/usr/local/openresty/nginx/sbin:$PATH
  * OSx 通过homebrew默认安装路径：
    * export PATH=/usr/local/opt/openresty/nginx/sbin:$PATH

**运行单个测试用例**

- 使用以下命令运行指定的测试用例：
  - prove -Itest-nginx/lib -r t/plugin/openid-connect.t

## 5. 更新 Admin API 的 token ，保护 Apache APISIX

修改 `conf/config.yaml` 中的 `apisix.admin_key` 并重启服务。例如下面例子：

```yaml
apisix:
  # ... ...
  admin_key
    -
      name: "admin"
      key: abcdefghabcdefgh
      role: admin
```

当我们需要访问 Admin API 时，就可以使用上面记录的 key 作为 token 了。

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

## 6. 为 APISIX 构建 OpenResty

有些功能需要你引入额外的 Nginx 模块到 OpenResty 当中。
如果你需要这些功能，你可以用[这个脚本](https://raw.githubusercontent.com/api7/apisix-build-tools/master/build-apisix-openresty.sh)
构建 OpenResty。

## 7. 为 APISIX 添加 systemd 配置文件

如果通过 rpm 包安装 APISIX，配置文件已经自动安装到位，你可以直接运行

```
$ systemctl start apisix
$ systemctl stop apisix
$ systemctl enable apisix
```

如果通过其他方法安装，可以参考[配置文件模板](https://github.com/api7/apisix-build-tools/blob/master/usr/lib/systemd/system/apisix.service)进行修改，并将其放置在 `/usr/lib/systemd/system/apisix.service`。
