---
title: 最少连接负载均衡器
keywords:
  - APISIX
  - API 网关
  - 路由
  - 最小连接
  - 上游
description: 本文介绍了 Apache APISIX 中的最少连接负载均衡器（`least_conn`），包括其工作原理、配置方法和使用场景。
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

## 概述

Apache APISIX 中的 `least_conn` 负载均衡器提供两种操作模式：

1. **传统模式**（默认）：性能优化的加权轮询算法
2. **持久化连接计数模式**：真正的最少连接算法，在负载均衡器重建过程中保持准确的连接计数

该算法特别适用于请求处理时间差异较大的场景，或处理长连接（如 WebSocket 连接）的情况，其中第二种模式在上游扩容后为负载分布提供显著优势。

## 算法详情

### 核心原理

#### 传统模式（默认）

在传统模式下，算法使用带有动态评分的加权轮询方法：

- 初始化每个服务器的分数 = `1 / weight`
- 连接时：分数增加 `1 / weight`
- 完成时：分数减少 `1 / weight`

这为大多数用例提供了良好的性能，同时保持向后兼容性。

#### 持久化连接计数模式

当启用时，算法在共享内存中为每个上游服务器维护准确的连接计数：

- 跨配置重载跟踪真实连接计数
- 在上游节点扩容操作中保持状态
- 为长连接提供真正的最少连接行为

该算法使用二进制最小堆数据结构来高效跟踪和选择得分最低的服务器。

### 得分计算

#### 传统模式

```lua
-- 初始化
score = 1 / weight

-- 连接时
score = score + (1 / weight)

-- 完成时
score = score - (1 / weight)
```

#### 持久化连接计数模式

```lua
-- 初始化和更新
score = (connection_count + 1) / weight
```

其中：

- `connection_count` - 服务器当前活跃连接数（持久化）
- `weight` - 服务器权重配置值

得分较低的服务器优先获得新连接。在持久化模式下，`+1` 代表正在考虑的潜在新连接。

### 连接状态管理

#### 传统模式

- **连接开始**：分数更新为 `score + (1 / weight)`
- **连接结束**：分数更新为 `score - (1 / weight)`
- **状态**：仅在当前负载均衡器实例内维护
- **堆维护**：二进制堆自动按得分重新排序服务器

#### 持久化连接计数模式

- **连接开始**：连接计数递增，得分更新为 `(new_count + 1) / weight`
- **连接结束**：连接计数递减，得分更新为 `(new_count - 1) / weight`
- **得分保护**：通过设置最小得分为 0 防止出现负分
- **堆维护**：二进制堆自动按得分重新排序服务器

##### 持久化策略

连接计数存储在 nginx 共享字典中，使用结构化键：

```
conn_count:{upstream_id}:{server_address}
```

这确保连接状态在以下情况下保持：

- 上游配置变更
- 负载均衡器实例重建
- 工作进程重启
- 上游节点扩容操作

### 连接跟踪

#### 持久状态管理

负载均衡器使用 nginx 共享字典（`balancer-least-conn`）在以下情况下维护连接计数：

- 负载均衡器实例重建
- 上游配置变更
- 工作进程重启
- 节点添加/移除

#### 连接计数键

连接计数使用结构化键存储：

```
conn_count:{upstream_id}:{server_address}
```

其中：

- `upstream_id` - 上游配置的唯一标识符
- `server_address` - 服务器地址（例如："127.0.0.1:8080"）

#### 上游 ID 生成

1. **主要方式**：如果可用，使用 `upstream.id`
2. **备用方式**：生成上游配置稳定 JSON 编码的 CRC32 哈希

```lua
local upstream_id = upstream.id
if not upstream_id then
    upstream_id = ngx.crc32_short(dkjson.encode(upstream))
end
```

实现使用 `dkjson.encode` 而不是 `core.json.encode` 来确保确定性的 JSON 序列化，这对于在不同工作进程和配置重载之间生成一致的上游 ID 至关重要。

### 连接生命周期

#### 1. 连接建立

当路由新请求时：

1. 从堆中选择得分最低的服务器
2. 将服务器得分更新为 `(current_count + 1) / weight`
3. 在共享字典中递增连接计数
4. 更新堆中服务器的位置

#### 2. 连接完成

当请求完成时：

1. 计算新得分为 `(current_count - 1) / weight`
2. 保证得分不为负（最小为 0）
3. 在共享字典中递减连接计数
4. 更新堆中服务器的位置

#### 3. 清理过程

在负载均衡器重建期间：

1. 识别当前活跃的服务器
2. 移除不再在上游中的服务器的连接计数
3. 保留现有服务器的计数

### 数据结构

#### 二进制堆

- **类型**：基于服务器得分的最小堆
- **目的**：高效选择得分最低的服务器
- **操作**：O(log n) 插入、删除和更新

#### 共享字典

- **名称**：`balancer-least-conn`
- **大小**：10MB（可配置）
- **范围**：在所有工作进程间共享
- **持久性**：在配置重载后保持

## 配置

### 自动设置

`balancer-least-conn` 共享字典由 APISIX 自动配置，默认大小为 10MB。无需手动配置。

### 自定义配置

要自定义共享字典大小，请修改 `conf/config.yaml` 中的 `nginx_config.http.lua_shared_dict` 部分：

```yaml
nginx_config:
  http:
    lua_shared_dict:
      balancer-least-conn: 20m  # 自定义大小（默认：10m）
```

### 上游配置

#### 传统模式（默认）

```yaml
upstreams:
  - id: 1
    type: least_conn
    nodes:
      "127.0.0.1:8080": 1
      "127.0.0.1:8081": 2
      "127.0.0.1:8082": 1
```

#### 持久化连接计数模式

##### WebSocket（自动启用）

```yaml
upstreams:
  - id: websocket_upstream
    type: least_conn
    scheme: websocket  # 自动启用持久化计数
    nodes:
      "127.0.0.1:8080": 1
      "127.0.0.1:8081": 1
      "127.0.0.1:8082": 1
```

##### 手动激活

```yaml
upstreams:
  - id: custom_upstream
    type: least_conn
    persistent_conn_counting: true  # 显式启用持久化计数
    nodes:
      "127.0.0.1:8080": 1
      "127.0.0.1:8081": 1
      "127.0.0.1:8082": 1
```

## 性能特征

### 时间复杂度

- **服务器选择**：O(1) - 堆查看操作
- **连接更新**：O(log n) - 堆更新操作
- **清理**：O(k)，其中 k 是存储键的数量

### 内存使用

- **每个服务器**：约 100 字节（键 + 值 + 开销）
- **总计**：与所有上游的服务器数量线性扩展

### 可扩展性

- **服务器**：高效处理每个上游数百个服务器
- **上游**：支持多个上游，具有隔离的连接跟踪
- **请求**：最小的每请求开销

## 使用场景

### 传统模式

#### 最佳场景

1. **高吞吐量 HTTP API**：快速、短连接
2. **微服务**：请求/响应模式  
3. **标准 Web 应用**：常规 HTTP 流量

#### 优势

- 较低的内存使用
- 短连接的更好性能
- 简单配置

### 持久化连接计数模式

#### 最佳场景

1. **WebSocket 应用**：长连接在扩容操作中受益于准确的负载分布
2. **服务器发送事件（SSE）**：持久流连接
3. **长轮询**：扩展的 HTTP 连接
4. **可变处理时间**：持续时间不可预测的请求
5. **数据库连接池**：面向连接的服务

#### 节点扩容后的使用

特别适用于以下情况：

- 向现有部署添加新的上游节点
- 现有长连接保留在原始节点上
- 需要在所有可用节点间平衡负载

### 注意事项

1. **短连接**：传统模式对于非常短的请求开销更低
2. **内存使用**：持久化模式需要共享内存来存储连接状态
3. **向后兼容性**：传统模式保持现有行为

## WebSocket 负载均衡改进

### 解决的问题

在此增强之前，当上游节点扩容（例如从 2 个节点扩展到 3 个节点）时，WebSocket 负载均衡会出现不平衡分布：

- 现有 WebSocket 长连接保留在原始节点上
- 新连接分布在所有节点上
- 结果：原始节点过载，新节点利用不足

### 解决方案

持久化连接计数模式专门通过以下方式解决此问题：

1. **跟踪真实连接**：在共享内存中维护准确的连接计数
2. **在扩容事件中保持状态**：连接计数在上游配置更改中持续存在
3. **平衡新连接**：新连接自动路由到负载较轻的节点
4. **逐步重平衡**：随着连接自然终止和重连，负载逐渐平衡

### 示例场景

**增强前：**

```
初始：Node1(50连接)，Node2(50连接)
扩容到3个节点后：Node1(50连接)，Node2(50连接)，Node3(0连接)
新连接分布：Node1(60连接)，Node2(60连接)，Node3(40连接)
```

**使用持久化计数：**

```
初始：Node1(50连接)，Node2(50连接)
扩容到3个节点后：Node1(50连接)，Node2(50连接)，Node3(0连接)
新连接路由到Node3直到平衡：Node1(50连接)，Node2(50连接)，Node3(50连接)
```

## 监控和调试

### 日志消息

#### 调试日志

启用调试日志来监控负载均衡器行为：

**负载均衡器创建**

```
creating new least_conn balancer for upstream: upstream_123
```

**连接数操作**

```
generated connection count key: conn_count:upstream_123:127.0.0.1:8080
retrieved connection count for 127.0.0.1:8080: 5
setting connection count for 127.0.0.1:8080 to 6
incrementing connection count for 127.0.0.1:8080 by 1, new count: 6
```

**服务器选择**

```
selected server: 127.0.0.1:8080 with current score: 1.2
after_balance for server: 127.0.0.1:8080, before_retry: false
```

**清理操作**

```
cleaning up stale connection counts for upstream: upstream_123
cleaned up stale connection count for server: 127.0.0.1:8082
```

#### 初始化

```
initializing server 127.0.0.1:8080 with weight 1, base_score 1, conn_count 0, final_score 1
```

#### 错误

```
failed to set connection count for 127.0.0.1:8080: no memory
failed to increment connection count for 127.0.0.1:8080: no memory
```

### 共享字典监控

检查共享字典使用情况：

```lua
local dict = ngx.shared["balancer-least-conn"]
local free_space = dict:free_space()
local capacity = dict:capacity()
```

## 错误处理

### 缺少共享字典

如果共享字典不可用（在默认配置下不应该发生），负载均衡器将初始化失败并显示：

```
shared dict 'balancer-least-conn' not found
```

### 内存耗尽

当共享字典内存不足时：

- 连接计数更新将失败
- 将记录警告消息
- 负载均衡器继续运行，但可能使用过时的计数

### 恢复策略

1. **增加字典大小**：分配更多内存
2. **清理频率**：实现过时条目的定期清理
3. **监控**：为字典使用情况设置警报

## 最佳实践

### 配置

1. **字典大小**：默认 10MB 对大多数情况足够（支持约 10 万连接）
2. **服务器权重**：使用适当的权重来反映服务器容量
3. **健康检查**：与健康检查结合使用以实现稳健的负载均衡

### 监控

1. **连接计数**：监控意外的累积
2. **内存使用**：跟踪共享字典利用率
3. **性能**：测量请求分布的有效性

### 故障排除

1. **不均匀分布**：检查连接计数累积
2. **内存问题**：监控共享字典可用空间
3. **配置**：验证共享字典是否正确配置

## 迁移和兼容性

### 向后兼容性

- 当共享字典不可用时优雅降级
- 对现有 API 无破坏性更改
- 保持现有行为模式

### 升级注意事项

1. **配置**：共享字典自动配置
2. **内存**：默认分配对大多数用例应该足够
3. **测试**：在测试环境中验证负载分布
