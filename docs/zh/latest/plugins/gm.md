---
title: GM
keywords:
  - Apache APISIX
  - Plugin
  - GM
description: 本文介绍了关于 Apache APISIX gm 插件的基本信息及使用方法。
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

## 描述

`gm` 插件能启用国密相关的功能。目前支持通过该插件动态配置国密双证书。

:::note 相关介绍
国密就是国产化的密码算法。在我们日常开发过程中会接触到各种各样的密码算法，如 RSA、SHA256 等等。为了达到更高的安全等级，许多大公司和国家会制定自己的密码算法。国密就是这样一组由中国国家密码管理局制定的密码算法。在国际形势越发复杂多变的今天，密码算法的国产化替代，在一些领域已经成为了一股势不可挡的潮流。
:::

## 启用插件

**该插件要求 Apache APISIX 运行在编译了 Tongsuo 的 APISIX-Runtime 上。**

首先，我们需要安装 Tongsuo（此处我们选择编译出 Tongsuo 的动态链接库）：

```
# TODO: use a fixed release once they have created one.
# See https://github.com/Tongsuo-Project/Tongsuo/issues/318
git clone https://github.com/api7/tongsuo --depth 1
pushd tongsuo
./config shared enable-ntls -g --prefix=/usr/local/tongsuo
make -j2
sudo make install_sw
```

其次，我们需要构建 APISIX-Runtime，让它使用 Tongsuo 作为 SSL 库：

```
export OR_PREFIX=/usr/local/openresty
export openssl_prefix=/usr/local/tongsuo
export zlib_prefix=$OR_PREFIX/zlib
export pcre_prefix=$OR_PREFIX/pcre

export cc_opt="-DNGX_LUA_ABORT_AT_PANIC -I${zlib_prefix}/include -I${pcre_prefix}/include -I${openssl_prefix}/include"
export ld_opt="-L${zlib_prefix}/lib -L${pcre_prefix}/lib -L${openssl_prefix}/lib64 -Wl,-rpath,${zlib_prefix}/lib:${pcre_prefix}/lib:${openssl_prefix}/lib64"
./build-apisix-runtime.sh
```

该插件默认是禁用状态，你需要将其添加到配置文件（`./conf/config.yaml`）中才可以启用它：

```yaml
plugins:
  - ...
  - gm
```

由于 APISIX 的默认 cipher 中不包含国密 cipher，所以我们还需要在配置文件（`./conf/config.yaml`）中设置 cipher：

```yaml
apisix:
  ...
  ssl:
    ...
    # 可按实际情况调整。错误的 cipher 会导致“no shared cipher”或“no ciphers available”报错。
    ssl_ciphers: HIGH:!aNULL:!MD5

```

配置完成后，重新加载 APISIX，此时 APISIX 将会启用国密相关的逻辑。

## 测试插件

在测试插件之前，我们需要准备好国密双证书。Tongsuo 提供了生成[SM2 双证书](https://www.yuque.com/tsdoc/ts/sulazb)的教程。

在下面的例子中，我们将用到如下的证书：

```
# 客户端加密证书和密钥
t/certs/client_enc.crt
t/certs/client_enc.key
# 客户端签名证书和密钥
t/certs/client_sign.crt
t/certs/client_sign.key
# CA 和中间 CA 打包在一起的文件，用于设置受信任的 CA
t/certs/gm_ca.crt
# 服务端加密证书和密钥
t/certs/server_enc.crt
t/certs/server_enc.key
# 服务端签名证书和密钥
t/certs/server_sign.crt
t/certs/server_sign.key
```

此外，我们还需要准备 Tongsuo 命令行工具。

```
./config enable-ntls -static
make -j2
# 生成的命令行工具在 apps 目录下
mv apps/openssl ..
```

你也可以采用非静态编译的方式，不过就需要根据具体环境，自己解决动态链接库的路径问题了。

以下示例展示了如何在指定域名中启用 `gm` 插件：

创建对应的 SSL 对象：

```python
#!/usr/bin/env python
# coding: utf-8

import sys
# sudo pip install requests
import requests

if len(sys.argv) <= 3:
    print("bad argument")
    sys.exit(1)
with open(sys.argv[1]) as f:
    enc_cert = f.read()
with open(sys.argv[2]) as f:
    enc_key = f.read()
with open(sys.argv[3]) as f:
    sign_cert = f.read()
with open(sys.argv[4]) as f:
    sign_key = f.read()
api_key = "edd1c9f034335f136f87ad84b625c8f1"
resp = requests.put("http://127.0.0.1:9180/apisix/admin/ssls/1", json={
    "cert": enc_cert,
    "key": enc_key,
    "certs": [sign_cert],
    "keys": [sign_key],
    "gm": True,
    "snis": ["localhost"],
}, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
```

将上面的脚本保存为 `./create_gm_ssl.py`，运行：

```shell
./create_gm_ssl.py t/certs/server_enc.crt  t/certs/server_enc.key t/certs/server_sign.crt t/certs/server_sign.key
```

输出结果如下所示：

```
200
{"key":"\/apisix\/ssls\/1","value":{"keys":["Yn...
```

完成上述准备后，可以使用如下命令测试插件是否启用成功：

```shell
./openssl s_client -connect localhost:9443 -servername localhost -cipher ECDHE-SM2-WITH-SM4-SM3 -enable_ntls -ntls -verifyCAfile t/certs/gm_ca.crt -sign_cert t/certs/client_sign.crt -sign_key t/certs/client_sign.key -enc_cert t/certs/client_enc.crt -enc_key t/certs/client_enc.key
```

这里 `./openssl` 是前面得到的 Tongsuo 命令行工具。9443 是 APISIX 默认的 HTTPS 端口。

如果一切正常，可以看到连接建立了起来，并输出如下信息：

```
...
New, NTLSv1.1, Cipher is ECDHE-SM2-SM4-CBC-SM3
...
```

## 删除插件

如果不再使用此插件，可将 `gm` 插件从 `./conf/config.yaml` 配置文件中移除，然后重启 APISIX 或者通过插件热加载的接口触发插件的卸载。
