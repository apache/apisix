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

该插件需要 [APISIX Runtime](../FAQ.md#如何构建-apisix-runtime-环境)：密钥保存在主级 `lua {}` 块的共享内存中，由 HTTP 与 Stream 子系统共用。

## 本地策略

本地配置决定是否使用共享密钥以及密钥的来源。这些属性不属于插件元数据，也不能通过 Admin API 修改。

```yaml title="./conf/config.yaml"
plugin_attr:
  ssl-session-ticket:
    enabled: false
    key_source: generated
```

| 名称       | 类型    | 必选项 | 默认值    | 有效值              | 描述 |
|------------|---------|--------|-----------|---------------------|------|
| enabled    | boolean | 否     | false     |                     | 为 true 时，为业务 TLS 监听发布密钥。通过 Admin API 提交的密钥本身不会启用该功能。 |
| key_source | string  | 否     | generated | generated、external | `generated`：由 APISIX 维护密钥，Admin API 拒绝对密钥的任何写入。`external`：由你通过 Admin API 提交完整的密钥集合。 |

`traditional` 与 `control_plane` 节点执行该策略，`data_plane` 节点忽略它。请在所有执行策略的节点上保持相同的配置。与 `config.yaml` 的其他修改一样，本地配置的修改在 reload 后生效。

standalone 模式（YAML、JSON 或 API 驱动）只支持 `external` 密钥，参见 [standalone 模式](#standalone-模式)。

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
| `key_source: generated`                   | `409`         | 由 APISIX 维护密钥。改为 `external` 后才能通过 Admin API 管理。 |

* `PUT` 整体替换密钥集合。内容和顺序都相同的密钥不会写入，也不会产生新的 revision，因此 ADC 等声明式工具可以反复提交同一组密钥。
* 请求体只接受 `keys`。其他字段一律拒绝，例如 `enabled`、`key_source`、`origin`、`id`、引用或单把密钥的时间字段。同样拒绝：不是合法 base64 的密钥、解码后不是 80 字节的密钥、重复的密钥、16 字节密钥名相同的两把密钥，以及超过 256 把密钥。非法请求整体拒绝：不写入任何内容，已保存的密钥保持不变。
* 密钥没有 TTL，拒绝 `ttl` 参数。
* 每次写入都以请求读到的 revision 原子提交。如果期间其他写入者修改了密钥，请求返回 `409` 且不写入任何内容，请重试。
* APISIX 会在保存的元数据中加入 `origin` 对象：密钥的来源、是否被本地策略停用，以及该策略的指纹。你不能设置它。
* 任何响应都不包含密钥，无论明文还是密文：它们被替换为 `<redacted>`。请自行保管密钥，`GET` 的结果不能再次提交。
* `apisix.data_encryption.enable_encrypt_fields` 为 true 时，密钥在写入 etcd 前用 `apisix.data_encryption.keyring` 加密。加密失败时请求失败，不写入任何内容。

## 使用示例

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

元数据只表示已保存的内容，不代表各节点正在使用的内容。每个节点的 Control API 在 [`GET /v1/tls_session_ticket`](../control-api.md#get-v1tls_session_ticket) 中报告本节点的状态：密钥的来源与 revision、密钥数量、本地版本与发布时间，以及安全告警。它从不返回密钥。

## 安全

* 一把密钥能解密它签发的所有 ticket。使用 TLS 1.2 时，取得密钥的人还能解密用这些 ticket 恢复的会话的录制流量。请用安全的随机数生成密钥、定期轮转，并限制对 Admin API 和 etcd 的访问。
* 所有节点使用同一组密钥，会扩大单个节点失陷的影响范围，因此 `enabled` 默认为 false。
* `apisix.data_encryption.enable_encrypt_fields` 为 false，或 `apisix.data_encryption.keyring` 仍包含默认配置中公开的示例密钥时，APISIX 会在日志中告警，Control API 的 `warnings` 中报告 `encryption_disabled` 或 `default_keyring`。密钥仍然可用，但请配置私有的 keyring，以保护 etcd 中的密钥。
* 密钥不会出现在 Admin API 的响应、Control API 的插件元数据导出或错误日志中，即使请求非法或不是合法的 JSON 也是如此。
