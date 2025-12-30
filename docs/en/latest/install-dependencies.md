---
title: Install Dependencies
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

## Note

- Since v2.0 Apache APISIX would not support the v2 protocol storage to etcd anymore, and the minimum etcd version supported is v3.4.0. What's more, etcd v3 uses gRPC as the messaging protocol, while Apache APISIX uses HTTP(S) to communicate with etcd cluster, so be sure the [etcd gRPC gateway](https://etcd.io/docs/v3.4.0/dev-guide/api_grpc_gateway/) is enabled.

- Now by default Apache APISIX uses HTTP protocol to talk with etcd cluster, which is insecure. Please configure certificate and corresponding private key for your etcd cluster, and use "https" scheme explicitly in the etcd endpoints list in your Apache APISIX configuration, if you want to keep the data secure and integral. See the etcd section in `conf/config.yaml.example` for more details.

- If it is OpenResty 1.19, APISIX will use OpenResty's built-in LuaJIT to run `bin/apisix`; otherwise it will use Lua 5.1. If you encounter `luajit: lj_asm_x86.h:2819: asm_loop_ fixup: Assertion '((intptr_t)target & 15) == 0' failed`, this is a problem with the low version of OpenResty's built-in LuaJIT under certain compilation conditions.

- On some platforms, installing LuaRocks via the package manager will cause Lua to be upgraded to Lua 5.3, so we recommend installing LuaRocks via source code. if you install OpenResty and its OpenSSL develop library (openresty-openssl111-devel for rpm and openresty-openssl111-dev for deb) via the official repository, then [we provide a script for automatic installation](https://github.com/apache/apisix/blob/master/utils/linux-install-luarocks.sh). If you compile OpenResty yourself, you can refer to the above script and change the path in it. If you don't specify the OpenSSL library path when you compile, you don't need to configure the OpenSSL variables in LuaRocks, because the system's OpenSSL is used by default. If the OpenSSL library is specified at compile time, then you need to ensure that LuaRocks' OpenSSL configuration is consistent with OpenResty's.

- OpenResty is a dependency of APISIX. If it is your first time to deploy APISIX and you don't need to use OpenResty to deploy other services, you can stop and disable OpenResty after installation since it will not affect the normal work of APISIX. Please operate carefully according to your service. For example in Ubuntu: `systemctl stop openresty && systemctl disable openresty`.

## Install

Run the following command to install Apache APISIX's dependencies on a supported operating system.

Supported OS versions: Debian 11/12, Ubuntu 20.04/22.04/24.04, etc.

Note that in the case of Arch Linux, we use `openresty` from the AUR, thus requiring a AUR helper. For now `yay` and `pacaur` are supported.

```
curl https://raw.githubusercontent.com/apache/apisix/master/utils/install-dependencies.sh -sL | bash -
```

If you have cloned the Apache APISIX project, execute in the Apache APISIX root directory:

```
bash utils/install-dependencies.sh
```
