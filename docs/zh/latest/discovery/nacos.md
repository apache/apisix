---
title: nacos
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

## 基于 [Nacos](https://nacos.io/zh-cn/docs/what-is-nacos.html) 的服务发现

当前模块的性能有待改进：

1. 并行发送请求。

### Nacos 配置

在文件 `conf/config.yaml` 中添加以下配置到：

```yaml
discovery:
  nacos:
    host:
      - "http://${username}:${password}@${host1}:${port1}"
    prefix: "/nacos/v1/"
    fetch_interval: 30    # default 30 sec
    weight: 100           # default 100
    timeout:
      connect: 2000       # default 2000 ms
      send: 2000          # default 2000 ms
      read: 5000          # default 5000 ms
```

也可以这样简洁配置（未配置项使用默认值）：

```yaml
discovery:
  nacos:
    host:
      - "http://192.168.33.1:8848"
```

### Upstream 设置

#### 七层

例如，转发 URI 匹配 "/nacos/*" 的请求到一个上游服务，
该服务在 Nacos 中的服务名是 APISIX-NACOS，查询地址是 http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS，创建路由时指定服务发现类型为 nacos。

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacos/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos"
    }
}'
```

响应如下：

```json
{
  "node": {
    "key": "\/apisix\/routes\/1",
    "value": {
      "id": "1",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos"
      },
      "priority": 0,
      "uri": "\/nacos\/*"
    }
  }
}
```

#### 四层

nacos 服务发现也支持在四层中使用，配置方式与七层的类似。

```shell
$ curl http://127.0.0.1:9180/apisix/admin/stream_routes/1 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "remote_addr": "127.0.0.1",
    "upstream": {
        "scheme": "tcp",
        "discovery_type": "nacos",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin"
    }
}'
```

### 参数

| 名字         | 类型   | 可选项 | 默认值 | 有效值 | 说明                                                  |
| ------------ | ------ | ----------- | ------- | ----- | ------------------------------------------------------------ |
| namespace_id | string | 可选    | public     |       | 服务所在的命名空间 |
| group_name   | string | 可选    | DEFAULT_GROUP       |       | 服务所在的组 |

#### 指定命名空间

例如，转发 URI 匹配 "/nacosWithNamespaceId/*" 的请求到一个上游服务，
该服务在 Nacos 中的服务名是 APISIX-NACOS，命名空间是 test_ns，查询地址是 http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS&namespaceId=test_ns，创建路由时指定服务发现类型为 nacos。

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/2 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacosWithNamespaceId/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "namespace_id": "test_ns"
        }
    }
}'
```

响应如下：

```json
{
  "node": {
    "key": "\/apisix\/routes\/2",
    "value": {
      "id": "2",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "namespace_id": "test_ns"
        }
      },
      "priority": 0,
      "uri": "\/nacosWithNamespaceId\/*"
    }
  }
}
```

#### 指定组

例如，转发 URI 匹配 "/nacosWithGroupName/*" 的请求到一个上游服务，
该服务在 Nacos 中的服务名是 APISIX-NACOS，组名是 test_group，查询地址是 http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS&groupName=test_group，创建路由时指定服务发现类型为 nacos。

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/3 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacosWithGroupName/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "group_name": "test_group"
        }
    }
}'
```

响应如下：

```json
{
  "node": {
    "key": "\/apisix\/routes\/3",
    "value": {
      "id": "3",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "group_name": "test_group"
        }
      },
      "priority": 0,
      "uri": "\/nacosWithGroupName\/*"
    }
  }
}
```

#### 同时指定命名空间和组

例如，转发 URI 匹配 "/nacosWithNamespaceIdAndGroupName/*" 的请求到一个上游服务，
该服务在 Nacos 中的服务名是 APISIX-NACOS，命名空间是 test_ns，组名是 test_group，查询地址是 http://192.168.33.1:8848/nacos/v1/ns/instance/list?serviceName=APISIX-NACOS&namespaceId=test_ns&groupName=test_group，创建路由时指定服务发现类型为 nacos。

```shell
$ curl http://127.0.0.1:9180/apisix/admin/routes/4 -H "X-API-KEY: $admin_key" -X PUT -i -d '
{
    "uri": "/nacosWithNamespaceIdAndGroupName/*",
    "upstream": {
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "namespace_id": "test_ns",
          "group_name": "test_group"
        }
    }
}'
```

响应如下：

```json
{
  "node": {
    "key": "\/apisix\/routes\/4",
    "value": {
      "id": "4",
      "create_time": 1615796097,
      "status": 1,
      "update_time": 1615799165,
      "upstream": {
        "hash_on": "vars",
        "pass_host": "pass",
        "scheme": "http",
        "service_name": "APISIX-NACOS",
        "type": "roundrobin",
        "discovery_type": "nacos",
        "discovery_args": {
          "namespace_id": "test_ns",
          "group_name": "test_group"
        }
      },
      "priority": 0,
      "uri": "\/nacosWithNamespaceIdAndGroupName\/*"
    }
  }
}
```
