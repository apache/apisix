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

#### 支持在apisix中使用nacos注册中心
   1. 参考官方euruka.lua实现
   2. 未对注册到nacos的实例做健康判断
   3. 只支持指定的namespace与group 
   4. 支持在nacos中配置元数据从而不注册到的apisix

----


#### 如何使用nacos提供服务发现功能

[1]  在 `conf/config.yaml` 文件中增加如下配置，以选择注册中心的类型：

```yaml
apisix:
  discovery: nacos 
```

[2]  在 `conf/config.yaml` 增加如下格式的配置：

```yaml
nacos:
  host:
    - "http://nacos:nacos@127.0.0.1:8848"     //用户名和密码使用冒号分隔
  prefix: "/nacos/"         
  namespace: public         //默认命名空间
  group: DEFAULT_GROUP      //默认分组
  fetch_interval: 30
  weight: 100
  timeout:
    connect: 2000
    send: 2000
    read: 5000

```
---

#### nacos元数据配置,用于取消注册服务或实例到apisix中
1. 支持配置在服务的元数据中,此时整个服务无法被apisix找到
2. 也支持配置在实例的元数据中，此时请求不会被转发到该实例

```json
{
	"apisix.gateway.registration": "false"
}
```
---

#### 为什么只支持指定的namespace和group

1. 获取nacos服务列表以及服务详情必须指定namespace或group,也无获取命名空间相关api, 但可以通过配置指定解决
2. apisix在通过upstrem.service_name配置路由的时候无法匹配更多metadata,导致即使获取了多个命名空间的实例,也无法正确路由到对的服务,反而破坏了服务的隔离性
