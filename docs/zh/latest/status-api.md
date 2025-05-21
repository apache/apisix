---
title: Status API
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

在 Apache APISIX 中，Status API 用于：

* 检查 APISIX 是否已成功启动并正确运行
* 检查所有 workers 是否已收到配置并加载

要更改 Status API 服务器的默认端点（`127.0.0.1:7085`），请更改配置文件（`conf/config.yaml`）中 `status` 部分中的 `ip` 和 `port`：

```yaml
apisix:
  status:
    ip: "127.0.0.1"
    port: 7085
```

此 API 可用于在 APISIX 开始接收用户请求之前对 APISIX 执行就绪探测。

### GET /status

返回报告 APISIX 工作人员状态的 JSON。如果 APISIX 未运行，建立 TCP 连接时请求将报错。否则，如果请求到达正在运行的 worker，此端点将始终返回 ok。

```json
{
  "status": "ok"
}
```

### GET /status/ready

当所有 worker 都已加载配置时，返回 `ok`；否则，返回特定错误，错误代码为 `503`。以下是具体示例。

当所有 worker 都已加载配置时：

```json
{
  "status": "ok"
}
```

当 1 个 workers 尚未初始化时：

```json
{
  "status": "error",
  "error": "worker count: 16 but status report count: 15"
}
```

当特定 worker 尚未加载配置时：

```json
{
  "error": "worker id: 9 has not received configuration",
  "status": "error"
}
```
