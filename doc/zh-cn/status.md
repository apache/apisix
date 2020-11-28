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

[English](../status.md)

## 内部状态

Apache APISIX 暴露了一系列运行时的内部状态数据，这提高了服务的可观测性，对于调试和监控是十分有帮助的。

## 服务信息

这是关于 APISIX 实例最基本的一些信息，你可以通过请求 admin api
`/apisix/admin/server_info` 来获取它们（请确保 config.yaml 文件中的 `allow_admin` 选项是被启用的）。

```bash
curl http://127.0.0.1:9080/apisix/admin/server_info -s | jq
{
  "up_time": 5,
  "last_report_time": 1606551536,
  "id": "71cb4999-4349-475d-aa39-c703944a63d3",
  "etcd_version": "3.5.0",
  "version": "2.0",
  "hostname": "gentoo"
}
```

服务信息中每一项的含义如下：

| Name    | Type | Description |
|---------|------|-------------|
| up_time | 整数 | APISIX 服务实例当前的运行时间, 如果对 APSIX
进行热更新操作，该值将被重置；普通的 reload 操作不会影响该值。|
| last_report_time | 整数 | 最近一次服务信息上报的时间戳 。|
| id | 字符串 | APISIX 服务实例 id 。 |
| etcd_version | 字符串 | etcd 集群的版本信息，如果 APISIX 和 etcd 集群之间存在网络分区，该值将设置为 `"unknown"`。 |
| version | 字符串 | APISIX 版本信息。 |
| hostname | 字符串 | APISIX 所部署的机器或 pod 的主机名信息。 |

注意服务信息将被周期性地上报到 etcd（目前的上报间隔是 5
秒）并被 APISIX Dashboard 所收集，所以你也可以通过 APISIX Dashboard 来访问这些数据。
