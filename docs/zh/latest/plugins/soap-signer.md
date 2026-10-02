---
title: soap-signer
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - SOAP
  - WS-Security
description: soap-signer 插件使用 X.509 WS-Security 签名为 SOAP 请求体签名。
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

`soap-signer` 插件使用 WS-Security 为 SOAP 1.1 和 SOAP 1.2 请求体签名。它会添加 `wsse:Security` 标头，其中包含 Timestamp、X.509 BinarySecurityToken，以及针对 SOAP Body 和 Timestamp 的 XML 签名。

插件支持日常使用的 RSA-SHA256，以及用于兼容旧版 SOAP 服务的 RSA-SHA1；使用不带注释的 exclusive XML canonicalization。默认情况下，插件通过 WS-Security `SecurityTokenReference` 引用已嵌入的证书。如果验证方通过带外方式获取证书，也可以省略 KeyInfo 和令牌。

同一个请求只能使用 `soap-signer` 和 `xml-signer` 中的一个。SOAP 也是 XML，两个插件都可以接受 `application/xml`；同时启用时，后执行的插件会拒绝已签名的消息。

## 工作原理

匹配的请求在 rewrite 阶段会依次执行以下操作：

1. 在禁用外部网络访问的情况下缓冲并解析 SOAP XML。
2. 根据 Envelope 命名空间识别 SOAP 1.1 或 SOAP 1.2，并按照 `soap.version` 验证版本。
3. 保留已有的 SOAP Header；若不存在，则在 Body 前创建。
4. 创建或复用 `wsse:Security`，并设置 SOAP `mustUnderstand` 属性。
5. 如果 Body 尚无 `wsu:Id`，则为其分配 ID。
6. 创建包含 `Created`、`Expires` 和唯一 `wsu:Id` 的 UTC Timestamp。
7. 除非 `signature.key_info` 为 `none`，否则在 `wsse:BinarySecurityToken` 中嵌入 X.509 证书。
8. 使用 `signature.algorithm` 指定的算法分别计算 Body 和 Timestamp 的摘要。
9. 对 canonicalized `ds:SignedInfo` 签名，并更新发往上游的请求体。

生成的安全标头大致如下：

```xml
<wsse:Security soap:mustUnderstand="...">
  <wsu:Timestamp wsu:Id="TS-...">
    <wsu:Created>...</wsu:Created>
    <wsu:Expires>...</wsu:Expires>
  </wsu:Timestamp>
  <wsse:BinarySecurityToken wsu:Id="X509-...">...</wsse:BinarySecurityToken>
  <ds:Signature>
    <ds:SignedInfo>
      <ds:Reference URI="#Body-...">...</ds:Reference>
      <ds:Reference URI="#TS-...">...</ds:Reference>
    </ds:SignedInfo>
    <ds:SignatureValue>...</ds:SignatureValue>
    <ds:KeyInfo>
      <wsse:SecurityTokenReference>
        <wsse:Reference URI="#X509-..." ValueType="...#X509v3"/>
      </wsse:SecurityTokenReference>
    </ds:KeyInfo>
  </ds:Signature>
</wsse:Security>
```

## 要求

- APISIX 必须运行在 Linux 上，并且系统中提供 `libxml2.so.2`。APISIX Debian 镜像已包含此库。
- 证书和私钥必须为 PEM 编码，使用 RSA，并且属于同一密钥对。
- SOAP 服务必须支持 X.509 BinarySecurityToken 直接引用和 exclusive XML canonicalization。
- 请将插件配置在所有其他修改 SOAP Body 或已签名标头的插件之后。此插件之后的任何修改都会使签名失效。

## 属性

| 名称 | 类型 | 必选 | 默认值 | 描述 |
| --- | --- | --- | --- | --- |
| `credentials` | object | 是 | | 签名凭据。 |
| `credentials.certificate` | string | 是 | | PEM 编码的 X.509 证书或 APISIX Secret 引用。 |
| `credentials.private_key` | string | 是 | | PEM 编码的 RSA 私钥或 APISIX Secret 引用。 |
| `signature` | object | 否 | `{}` | 签名配置。 |
| `signature.algorithm` | string | 否 | `rsa-sha256` | 签名和引用摘要算法。可选值为 `rsa-sha256` 和 `rsa-sha1`。 |
| `signature.key_info` | string | 否 | `binary_security_token` | 密钥信息模式。使用 `binary_security_token` 直接引用 X.509 令牌，或使用 `none` 同时省略 `ds:KeyInfo` 和令牌。 |
| `soap.version` | string | 否 | `auto` | SOAP 版本：`auto`、`1.1` 或 `1.2`。 |
| `soap.must_understand` | boolean | 否 | `true` | Security 标头中 SOAP `mustUnderstand` 属性的值。 |
| `timestamp.ttl_seconds` | integer | 否 | `300` | Timestamp 有效期，有效范围为 1 到 86400 秒。 |
| `request.methods` | array[string] | 否 | `["POST"]` | 要签名的请求方法。其他方法的请求保持不变并直接转发。 |
| `request.content_types` | array[string] | 否 | `["text/xml", "application/soap+xml", "application/xml"]` | 接受的媒体类型。 |
| `request.max_body_bytes` | integer | 否 | `5242880` | 请求体最大字节数，有效范围为 1024 到 67108864。 |

注意：schema 中定义了 `encrypt_fields = {"credentials.private_key"}`，因此直接配置的私钥会在 etcd 中加密。建议使用 [APISIX Secret](../terminology/secret.md) 引用，避免密钥材料保存在路由配置中。

### 签名算法

| 值 | SignatureMethod URI | DigestMethod URI | 用途 |
| --- | --- | --- | --- |
| `rsa-sha256` | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha256` | `http://www.w3.org/2001/04/xmlenc#sha256` | 默认且推荐。 |
| `rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#sha1` | 仅用于兼容旧版 WS-Security。 |

:::warning

SHA-1 在密码学上较弱。只有无法验证 RSA-SHA256 签名的旧版 SOAP 服务才应启用该算法。APISIX 每次使用 `rsa-sha1` 对请求签名时都会记录警告。请使用 TLS、限制网络访问、定期轮换凭据，并制定迁移到 RSA-SHA256 的计划。

:::

### SOAP 版本行为

| `soap.version` | 行为 |
| --- | --- |
| `auto` | 接受 SOAP 1.1 或 SOAP 1.2，并根据 Envelope 命名空间确定属性。 |
| `1.1` | 要求命名空间为 `http://schemas.xmlsoap.org/soap/envelope/`。`mustUnderstand` 序列化为 `1` 或 `0`。 |
| `1.2` | 要求命名空间为 `http://www.w3.org/2003/05/soap-envelope`。`mustUnderstand` 序列化为 `true` 或 `false`。 |

## 配置凭据

请使用 [APISIX Secret](../terminology/secret.md) 引用，避免私钥材料出现在路由配置中。格式如下：

```text
$secret://<manager>/<configuration-id>/<key-path>
```

例如：

```json
{
  "credentials": {
    "certificate": "$secret://vault/signing/soap/certificate",
    "private_key": "$secret://vault/signing/soap/private-key"
  }
}
```

APISIX 会在插件执行前解析引用。解析后的凭据会在每个 worker 中按解析值的指纹缓存。APISIX Secret 缓存刷新后，插件会使用轮换后的 Secret 值，无需重启 worker。

## 启用插件

以下示例启用 SOAP 版本自动检测和 RSA-SHA256：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-soap",
  "plugins": {
    "soap-signer": {
      "credentials": {
        "certificate": "$secret://vault/signing/soap/certificate",
        "private_key": "$secret://vault/signing/soap/private-key"
      },
      "signature": {"algorithm": "rsa-sha256"},
      "soap": {"version": "auto", "must_understand": true},
      "timestamp": {"ttl_seconds": 300}
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {"127.0.0.1:9001": 1}
  }
}'
```

对于只接受 SHA-1 的旧版服务，请使用：

```json
{
  "signature": {"algorithm": "rsa-sha1"}
}
```

这会同时更改 Body/Timestamp 摘要和 SignedInfo 签名，不会改变 canonicalization 或 BinarySecurityToken 格式。

## 禁用 KeyInfo

如果 SOAP 服务已配置签名证书且要求不包含 `ds:KeyInfo`，请将 `signature.key_info` 设为 `none`。此模式下插件也会省略 `wsse:BinarySecurityToken`，因为没有生成的元素会引用它。Body 和 Timestamp 仍会参与签名。

插件仍要求同时提供两种凭据：私钥用于签名，证书用于验证配置的密钥对是否匹配。

以下 Admin API 请求会创建不包含 KeyInfo 的 SOAP 路由：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/2 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-soap-without-key-info",
  "plugins": {
    "soap-signer": {
      "credentials": {
        "certificate": "$secret://vault/signing/soap/certificate",
        "private_key": "$secret://vault/signing/soap/private-key"
      },
      "signature": {
        "algorithm": "rsa-sha256",
        "key_info": "none"
      },
      "soap": {"version": "auto", "must_understand": true},
      "timestamp": {"ttl_seconds": 300}
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {"127.0.0.1:9001": 1}
  }
}'
```

生成的 `wsse:Security` 标头仍包含 Timestamp 和 `ds:Signature`，以及对 Body 和 Timestamp 的引用，但不包含 `wsse:BinarySecurityToken` 或 `ds:KeyInfo`。上游必须通过自身配置选择可信的验证证书。

## 使用示例

发送 SOAP 1.2 请求：

```shell
curl http://127.0.0.1:9080/signed-soap \
  -H "Content-Type: application/soap+xml" \
  -d '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><Ping/></s:Body></s:Envelope>'
```

对于 SOAP 1.1，请使用 `Content-Type: text/xml` 和 SOAP 1.1 Envelope 命名空间：

```shell
curl http://127.0.0.1:9080/signed-soap \
  -H "Content-Type: text/xml; charset=utf-8" \
  -d '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><Ping/></s:Body></s:Envelope>'
```

上游会收到包含已签名 WS-Security 标头的原始 SOAP 消息。请求方法未列入 `request.methods` 时，请求会保持不变并直接转发。

## 错误响应

| HTTP 状态码 | 消息 | 原因 |
| --- | --- | --- |
| `400` | `empty_body` | 被选中的请求没有请求体。 |
| `400` | `invalid_soap` | XML 解析失败、Body 缺失、存在重复 `wsu:Id`，或存在 DTD/实体声明。 |
| `400` | `not_soap` | 根元素不是受支持的 SOAP Envelope，或与 `soap.version` 不匹配。 |
| `400` | `already_signed` | 消息已包含 `ds:Signature`。 |
| `413` | `body_too_large` | 请求体超过 `request.max_body_bytes`。 |
| `415` | `unsupported_media_type` | 请求方法匹配，但 Content-Type 未列入 `request.content_types`。 |
| `500` | `credential_error` | Secret 解析失败、PEM 解析失败、密钥不是 RSA，或证书与私钥不匹配。 |
| `500` | `signing_error` | ID 生成、canonicalization、摘要生成、签名或序列化失败。 |

不会向客户端返回详细的密码学信息或请求内容。

## 限制

- 仅对 SOAP Body 和生成的 Timestamp 签名；目前不能将自定义 SOAP 标头添加为签名目标。
- KeyInfo 仅支持 X.509 BinarySecurityToken 直接引用或省略；不支持其他 KeyInfo 格式。
- 不支持 Actor/Role 定向、thumbprint 引用、ECDSA、RSA-PSS 或替换已有签名。
- 签名前会缓冲整个请求体；此操作不是流式签名。

## 故障排查

- 如果服务报告摘要不匹配，请确认没有优先级更低的插件或上游代理修改 Body、Timestamp、命名空间声明或 ID。
- 如果 APISIX 返回 `not_soap`，请根据 Envelope 命名空间检查 `soap.version`，不要只依赖 Content-Type。
- 如果 APISIX 返回 `credential_error`，请检查 Secret URI、PEM 边界、RSA 密钥类型以及证书与私钥是否匹配。
- 如果旧版服务拒绝 RSA-SHA256，请先将其预期算法 URI 与上表比较，再考虑启用 `rsa-sha1`。
- 如果服务拒绝 `mustUnderstand`，请确认它要求 SOAP 1.1 的数字值还是 SOAP 1.2 的布尔值。

## 删除插件

从路由插件配置中移除 `soap-signer`，并通过 Admin API 更新路由。APISIX 无需重启即可应用此更改。