---
title: brotli
keywords:
  - Apache APISIX
  - API 网关
  - Plugin
  - brotli
description: 这个文档包含有关 Apache APISIX brotli 插件的相关信息。
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

`brotli` 插件可以动态的设置 Nginx 中的 [brotli](https://github.com/google/ngx_brotli) 的行为。

## 前提条件

该插件依赖 brotli 共享库。

如下是构建和安装 brotli 共享库的示例脚本：

``` shell
wget https://github.com/google/brotli/archive/refs/tags/v1.1.0.zip
unzip v1.1.0.zip
cd brotli-1.1.0 && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local/brotli ..
sudo cmake --build . --config Release --target install
sudo sh -c "echo /usr/local/brotli/lib >> /etc/ld.so.conf.d/brotli.conf"
sudo ldconfig
```

## 属性

| 名称           | 类型                   | 必选项   | 默认值           | 有效值 | 描述                                                                                                                                         |
|--------------|----------------------|-------|---------------|--------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| types        | array[string] or "*" | False | ["text/html"] |              | 动态设置 `brotli_types` 指令。特殊值 `"*"` 用于匹配任意的 MIME 类型。                                                                                          |
| min_length   | integer              | False | 20            | >= 1         | 动态设置 `brotli_min_length` 指令。                                                                                                               |
| comp_level   | integer              | False | 6             | [0, 11]      | 动态设置 `brotli_comp_level` 指令。                                                                                                               |
| mode         | integer              | False | 0             | [0, 2]       | 动态设置 `brotli decompress mode`，更多信息参考 [RFC 7932](https://tools.ietf.org/html/rfc7932)。                                                      |
| lgwin        | integer              | False | 19            | [0, 10-24]   | 动态设置 `brotli sliding window size`，`lgwin` 是滑动窗口大小的以 2 为底的对数，将其设置为 0 会让压缩器自行决定最佳值，更多信息请参考 [RFC 7932](https://tools.ietf.org/html/rfc7932)。  |
| lgblock      | integer              | False | 0             | [0, 16-24]   | 动态设置 `brotli input block size`，`lgblock` 是最大输入块大小的以 2 为底的对数，将其设置为 0 会让压缩器自行决定最佳值，更多信息请参考 [RFC 7932](https://tools.ietf.org/html/rfc7932)。	 |
| http_version | number               | False | 1.1           | 1.1, 1.0     | 与 `gzip_http_version` 指令类似，用于识别 http 的协议版本。                                                                                                |
| vary         | boolean              | False | false         |              | 与 `gzip_vary` 指令类似，用于启用或禁用 `Vary: Accept-Encoding` 响应头。                                                                                    |

## 启用插件

如下示例中，在指定的路由上启用 `brotli` 插件：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl -i http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/",
    "plugins": {
        "brotli": {
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```

## 使用示例

通过上述命令启用插件后，可以通过以下方法测试插件：

```shell
curl http://127.0.0.1:9080/ -i -H "Accept-Encoding: br"
```

```
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Date: Tue, 05 Dec 2023 03:06:49 GMT
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Server: APISIX/3.6.0
Content-Encoding: br

Warning: Binary output can mess up your terminal. Use "--output -" to tell
Warning: curl to output it to your terminal anyway, or consider "--output
Warning: <FILE>" to save to a file.
```

## 删除插件

当您需要禁用 `brotli` 插件时，可以通过以下命令删除相应的 JSON 配置，APISIX 将会自动重新加载相关配置，无需重启服务：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```
