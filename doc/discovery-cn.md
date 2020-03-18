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

# 集成服务发现注册中心

## 开启服务发现

首先要在 conf/config.yaml 文件中增加如下配置，以选择注册中心的类型：

```yaml
apisix:
  discovery:
    type: eureka
```

## Eureka 的配置

在 `conf/apisix.yaml` 或 配置中心 增加如下配置：

```yaml
eureka:
  client:
    service_url:
      default_zone: "https://${usename}:${passowrd}@${eureka_host1}/eureka/,https://${usename}:${passowrd}@${eureka_host2}/eureka/"
```

