---
title: ssl-session-ticket
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - ssl-session-ticket
  - TLS session ticket
description: ssl-session-ticket 插件让各个 APISIX 节点的业务 TLS 监听共享同一组 TLS session ticket 密钥。
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

借助 TLS session ticket，客户端无需完整握手即可恢复 TLS 会话。服务端用 ticket 密钥把会话加密成 ticket 交给客户端保存，只要节点持有同一把密钥，客户端连到任意节点都能恢复会话。`ssl-session-ticket` 插件为共享同一份配置的所有 APISIX 节点提供一组有序的 ticket 密钥：第一把密钥签发 ticket，组内每一把密钥都能解密 ticket。

这些密钥面向承载业务流量的 TLS 监听：HTTPS，以及终止 TLS 的 Stream 代理。Admin API、Control API 等管理监听保持各自的 TLS 配置。

该插件是全局系统插件：只能通过插件元数据配置，没有请求阶段逻辑，不能绑定到路由、服务或消费者。它默认同时启用在 `plugins` 和 `stream_plugins` 中，因此纯 Stream 部署也能取得密钥。

该插件需要 [APISIX Runtime](../FAQ.md#如何构建-apisix-runtime-环境)：密钥保存在主级 `lua {}` 块的共享内存中，由 HTTP 与 Stream 子系统共用。业务 TLS 监听只有在 APISIX Runtime 接管其 session ticket 密钥时才会使用这些密钥，参见[业务 TLS 监听](#业务-tls-监听)。

## 本地策略

本地配置决定是否使用共享密钥以及密钥的来源。这些属性不属于插件元数据，也不能通过 Admin API 修改。

```yaml title="./conf/config.yaml"
plugin_attr:
  ssl-session-ticket:
    enabled: false
    key_source: generated
    generated:
      rotation_interval: 3600
      max_keys: 19
```

| 名称                        | 类型    | 必选项 | 默认值    | 有效值              | 描述 |
|-----------------------------|---------|--------|-----------|---------------------|------|
| enabled                     | boolean | 否     | false     |                     | 为 true 时，为业务 TLS 监听发布密钥。通过 Admin API 提交的密钥本身不会启用该功能。 |
| key_source                  | string  | 否     | generated | generated、external | `generated`：由 APISIX 生成并轮转密钥（参见[内置生成](#内置生成)），Admin API 拒绝对密钥的任何写入。`external`：由你通过 Admin API 提交完整的密钥集合。 |
| generated.rotation_interval | integer | 否     | 3600      | >= 60               | 两把签发 ticket 的新密钥之间相隔的秒数。仅用于 `generated`。 |
| generated.max_keys          | integer | 否     | 19        | [1, 256]            | 保留的密钥数量，包括正在签发 ticket 的那一把。仅用于 `generated`。 |

APISIX 启动时会校验这些属性。请在所有执行策略的节点上保持相同的配置，参见[策略一致性](#策略一致性)。与 `config.yaml` 的其他修改一样，本地配置的修改在 reload 后生效。

| 部署形态                                       | 本地策略 | 密钥 |
|------------------------------------------------|----------|------|
| 使用 etcd 的 `traditional` 与 `control_plane` | 执行：生成密钥，或通过 Admin API 接收外部密钥，并让元数据与 `enabled`、`key_source` 保持一致。 | 本节点使用。 |
| `data_plane`                                   | 忽略。 | 使用执行策略的节点发布的密钥。 |
| standalone（YAML、JSON 或 API 驱动）           | 只支持 `external` 密钥，是否使用由 `enabled` 决定。`enabled: true` 且 `key_source: generated` 时启动失败。 | 取自配置，参见 [standalone 模式](#standalone-模式)。 |
| 纯 Stream（`proxy_mode: stream`）              | 不执行：生成器运行在 HTTP 子系统的特权进程中。 | 使用其他节点发布的密钥。 |

## 业务 TLS 监听

每个 worker 进程把已发布的密钥应用到承载业务流量的 TLS 监听上，HTTP 与 Stream 子系统各自独立进行：

* `apisix.ssl.listen` 的 HTTPS 监听，包括 HTTP/3；
* `apisix.stream_proxy.tcp` 中 `tls: true` 的 Stream 监听，包括同时设置了 `tls_passthrough: true` 的监听上负责终止 TLS 的内部 server。

Admin API、Control API、Status API、Prometheus 导出服务、Stream 的 TLS 透传、普通 TCP 与 UDP，以及到上游的 TLS 连接都保持各自的配置。

worker 会在一秒内应用新的密钥集合，并在每个新连接到达 ClientHello 时让该连接与之对齐，不需要等待握手发生。监听只有在完整的密钥集合安装好之后才签发无状态 ticket，移除密钥之前先停止签发和接受 ticket。更换密钥不会关闭任何连接。

本地开关 `apisix.ssl.ssl_session_tickets` 决定本节点的业务监听是否使用共享密钥，未设置为 false 时即为 true。开关为 false，或者没有可用的密钥（插件未启用，密钥被停用、为空或无法加载）时，业务监听不签发无状态 ticket：

* TLS 1.2 下，客户端只能通过节点的会话缓存恢复会话。HTTPS 监听有会话缓存（`shared:SSL:20m`，10 分钟），Stream 监听没有。
* TLS 1.3 下，HTTPS 监听仍会发送其会话缓存的有状态 ticket，它只能在同一节点上恢复。

该接管需要 `apisix-nginx-module` 提供这一能力的 APISIX Runtime。使用较早的 APISIX Runtime 时，监听保持之前版本的行为：密钥照常发布，但 TLS 监听不使用它们，Control API 报告 `module_not_active`。

## 内置生成

`enabled: true` 且 `key_source: generated` 时，每个执行本地策略的节点的特权进程每隔几秒检查一次密钥：

* 没有密钥时，用密码学安全的随机数生成第一把密钥。
* 距上次生成已过 `rotation_interval` 秒时，在最前面加入一把新密钥（此后由它签发 ticket），并移除超出 `max_keys` 的最旧的密钥。按默认值，一把密钥签发 ticket 1 小时，之后再解密 18 小时。
* 上次生成的时间与密钥一同保存：重启节点不会重新计时；长时间停机后恢复的节点只轮转一次，不会为错过的每个周期各轮转一次。
* 调低 `max_keys` 会立即移除超出的密钥。

节点以读到的 revision 用 etcd 事务写入密钥：多个节点同时到期时，只有一个节点写入，其他节点读取它写入的密钥。节点生成或加密密钥失败时不写入任何内容，正在使用的密钥保持不变。

执行本地策略的节点还会让元数据与策略保持一致：

* `enabled: false` 时，密钥被标记为停用并保留在元数据中，TLS 监听停止使用它们。重新启用后继续使用这些密钥，之后的轮转会逐步替换它们。
* 切换到 `external` 时，生成的密钥被替换为空集合，等待你提交密钥。切换到 `generated` 时，外部密钥被替换为一把新生成的密钥。一种来源的密钥不会被当作另一种来源的密钥使用。

无法读取当前密钥的节点（例如它的 `apisix.data_encryption.keyring` 与其他节点不同）不会覆盖这些密钥，Control API 会报告该错误。

### 策略一致性

每个执行本地策略的节点都会在 etcd 的 `/apisix/ssl_session_ticket/policy/` 下登记其策略的指纹，所用租约在节点停止约 30 秒后结束。只要已登记的节点的策略不完全相同，它们都会停止生成密钥和改写元数据，Admin API 对元数据的写入返回 `409`。Control API 在 `generator.state` 中报告 `conflict`，错误日志会说明原因。所有节点的配置一致后会自动恢复。因此，滚动修改策略期间轮转会暂停一段时间，已发布的密钥继续有效。

## 插件元数据

`key_source: external` 时，向 `ssl-session-ticket` 的插件元数据提交完整的密钥集合：

| 名称 | 类型          | 必选项 | 描述 |
|------|---------------|--------|------|
| keys | array[string] | 是     | 完整、有序的密钥集合。每把密钥是 80 个随机字节的 base64 编码。第一把密钥签发 ticket，所有密钥都能解密 ticket。最多 256 把。空数组表示没有共享密钥。 |

一把密钥的 80 个字节依次是 16 字节的密钥名、32 字节的 HMAC 密钥和 32 字节的 AES 密钥，与 NGINX [ssl_session_ticket_key](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_session_ticket_key) 文件的格式相同。请用密码学安全的随机数生成每一把密钥，例如：

```shell
openssl rand 80 | base64 -w 0
```

Admin API 对 `ssl-session-ticket` 元数据执行以下规则：

| 本地策略                                  | PUT 与 DELETE | 效果 |
|-------------------------------------------|---------------|------|
| `enabled: false`、`key_source: external`  | 允许          | 保存密钥并标记为停用，不会使用。 |
| `enabled: true`、`key_source: external`   | 允许          | 按提交的内容原样使用：APISIX 不会增加、过期、轮转或移除任何密钥。 |
| `key_source: generated`                   | `409`         | 由 APISIX 生成密钥。改为 `external` 后才能通过 Admin API 管理。 |

* `PUT` 整体替换密钥集合。内容和顺序都相同的密钥不会写入，也不会产生新的 revision，因此 ADC 等声明式工具可以反复提交同一组密钥。
* 请求体只接受 `keys`。其他字段一律拒绝，例如 `enabled`、`key_source`、`origin`、`id`、引用或单把密钥的时间字段。同样拒绝：不是合法 base64 的密钥、解码后不是 80 字节的密钥、重复的密钥、16 字节密钥名相同的两把密钥，以及超过 256 把密钥。非法请求整体拒绝：不写入任何内容，已保存的密钥保持不变。
* 密钥没有 TTL，拒绝 `ttl` 参数。
* 每次写入都以请求读到的 revision 原子提交。如果期间其他写入者修改了密钥，请求返回 `409` 且不写入任何内容，请重试。
* 只要执行本地策略的节点的策略不完全相同，写入就会返回 `409`，参见[策略一致性](#策略一致性)。
* APISIX 会在保存的元数据中加入 `origin` 对象：密钥的来源、是否被本地策略停用，以及该策略的指纹。你不能设置它。
* 任何响应都不包含密钥，无论明文还是密文：它们被替换为 `<redacted>`。请自行保管密钥，`GET` 的结果不能再次提交。
* `apisix.data_encryption.enable_encrypt_fields` 为 true 时，密钥在写入 etcd 前用 `apisix.data_encryption.keyring` 加密。加密失败时请求失败，不写入任何内容。

## 使用示例

### 使用内置生成的密钥

在执行本地策略的节点上启用内置生成，然后 reload APISIX：

```yaml title="./conf/config.yaml"
plugin_attr:
  ssl-session-ticket:
    enabled: true
```

在任意节点上确认密钥已就绪：

```shell
curl http://127.0.0.1:9090/v1/tls_session_ticket
```

响应中报告 `"source": "generated"` 与密钥数量；在生成密钥的节点上，还有 `generator` 对象，其中 `"state": "ok"`。

### 使用外部密钥

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

在执行本地策略的节点上选择外部密钥，然后 reload APISIX：

```yaml title="./conf/config.yaml"
plugin_attr:
  ssl-session-ticket:
    enabled: true
    key_source: external
```

提交第一把密钥：

```shell
K1=$(openssl rand 80 | base64 -w 0)

curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/ssl-session-ticket \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "keys": ["'"$K1"'"]
}'
```

```json
{
  "key": "/apisix/plugin_metadata/ssl-session-ticket",
  "value": {
    "id": "ssl-session-ticket",
    "keys": ["<redacted>"],
    "origin": {
      "source": "external",
      "disabled": false,
      "policy": "1d6de6a6"
    }
  }
}
```

轮转时，把新密钥放在第一位并保留上一把，用上一把签发的 ticket 仍可恢复：

```shell
K2=$(openssl rand 80 | base64 -w 0)

curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/ssl-session-ticket \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "keys": ["'"$K2"'", "'"$K1"'"]
}'
```

下一次轮转提交 `[K3, K2]`，以此类推，每次请求都携带完整的集合。如需在新密钥开始签发前预先分发，先提交 `[K1, K2]`，再提交 `[K2, K1]`。

清除外部密钥时，提交空数组或删除该元数据：

```shell
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/ssl-session-ticket \
  -H "X-API-KEY: $admin_key" -X DELETE
```

## standalone 模式

standalone 配置在插件元数据中携带密钥，不需要 `origin`：

```yaml title="./conf/apisix.yaml"
plugin_metadata:
  - id: ssl-session-ticket
    keys:
      - <80 个随机字节的 base64 编码>
#END
```

这些密钥视为外部密钥，是否使用由本地的 `enabled` 属性决定，修改按配置版本排序。standalone 模式下 `origin.source` 为 `generated` 的记录无效。

## 状态

元数据只表示已保存的内容，不代表各节点正在使用的内容。每个节点的 Control API 在 [`GET /v1/tls_session_ticket`](../control-api.md#get-v1tls_session_ticket) 中报告本节点的状态：密钥的来源与 revision、密钥数量、本地版本与发布时间、各子系统已应用该版本的 worker 进程数、执行本地策略的节点上生成器的状态，以及安全告警。它从不返回密钥。

* `ok`：本节点所有业务 TLS 监听都在使用当前密钥。
* `off`：本节点所有业务 TLS 监听都已停止使用共享密钥，原因是本地开关（`local_switch_off`）、本地策略（`disabled_by_policy`），或者没有密钥（`empty_keys`，插件未启用时也是如此）。没有任何业务 TLS 监听的节点同样为 `off`。
* `degraded`：有 worker 尚未应用当前密钥（`worker_lag`），或者发生了故障（`invalid_state`、`module_not_active`、`apply_failed`）。应用失败的监听不使用任何共享密钥，节点在故障消除前一直为 `degraded`，原因见 `last_apply_error`。

要确认新密钥已经生效，或已停用的密钥不再使用，请逐个查询节点：把 `source_version` 与元数据的 revision 对比，再检查 `status` 与 `fully_applied`。仍在运行的旧配置代 worker 也计入其中，见 `draining`。

无法访问 etcd 的节点会一直保留已有的密钥，没有时间限制：没有任何机制会撤销收不到更新的节点上的密钥。需要紧急撤回密钥时，请停用或替换密钥，确认每个节点都已报告该结果，并停止或隔离没有报告的节点。

## 升级说明

使用接管 session ticket 密钥的 APISIX Runtime 时：

* `apisix.ssl.ssl_session_tickets` 对业务 HTTPS 监听的含义改变了。以前 `true` 打开 NGINX 原生的 session ticket，使用每个节点各自的随机密钥；现在它表示允许使用共享密钥，没有共享密钥时这些监听不签发无状态 ticket。未设置时现在等同于 true：没有发布密钥时，HTTPS 监听与以前的默认值一样不签发无状态 ticket。
* Stream TLS 监听以前使用 NGINX 原生的 session ticket，每个 worker 进程各自使用随机密钥；现在只用共享密钥签发 ticket，没有密钥时 Stream TLS 会话不能恢复。
* Admin API 不受影响：仍然只在 `apisix.ssl.ssl_session_tickets` 显式为 true 时使用 NGINX 原生的 session ticket。
* 以前打开了 session ticket 的配置不会自动恢复 ticket：请启用插件并提供密钥，参见[使用示例](#使用示例)。

## 安全

* 一把密钥能解密它签发的所有 ticket。使用 TLS 1.2 时，取得密钥的人还能解密用这些 ticket 恢复的会话的录制流量。请用安全的随机数生成密钥、定期轮转，并限制对 Admin API 和 etcd 的访问。
* 所有节点使用同一组密钥，会扩大单个节点失陷的影响范围，因此 `enabled` 默认为 false。节点会一直使用已有的密钥，直到收到新的密钥，参见[状态](#状态)。
* `apisix.data_encryption.enable_encrypt_fields` 为 false，或 `apisix.data_encryption.keyring` 仍包含默认配置中公开的示例密钥时，APISIX 会在日志中告警，Control API 的 `warnings` 中报告 `encryption_disabled` 或 `default_keyring`。密钥仍然可用，但请配置私有的 keyring，以保护 etcd 中的密钥。
* 密钥不会出现在 Admin API 的响应、Control API 的插件元数据导出或错误日志中，即使请求非法或不是合法的 JSON 也是如此。
