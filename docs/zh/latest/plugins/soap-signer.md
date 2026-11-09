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

不要在同一个路由中将本插件与其他请求签名插件组合使用。本插件会拒绝已经包含 XML 签名的消息。

:::caution

插件会使用配置的私钥为到达它的每个格式正确的 SOAP 消息签名。默认情况下（`request.require_consumer` 为 `true`），插件只为已由认证插件（例如 [`key-auth`](key-auth.md) 或 [`jwt-auth`](jwt-auth.md)）关联到消费者的请求签名，否则返回 `401`。认证插件会在 `soap-signer` 之前执行。认证插件上配置的 `anonymous_consumer` 同样满足此检查，因此不要在签名路由上配置匿名消费者。只有当路由已通过其他方式受到保护（例如 mTLS、`ip-restriction` 或 `forward-auth`）时，才应将 `request.require_consumer` 设置为 `false`。

:::

## 工作原理

匹配的请求在 rewrite 阶段会依次执行以下操作：

1. 当 `request.require_consumer` 为 `true` 时，如果请求未被认证插件关联到消费者，则返回 `401`。
2. 在禁用外部网络访问的情况下缓冲并解析 SOAP XML。
3. 根据 Envelope 命名空间识别 SOAP 1.1 或 SOAP 1.2，并按照 `soap.version` 验证版本。
4. 保留已有的 SOAP Header（必须位于 Body 之前）；若不存在，则在 Body 前创建。
5. 创建或复用 `wsse:Security`，并设置 SOAP `mustUnderstand` 属性；除非 `soap.allow_existing_security_content` 为 `true`，否则被复用的标头必须为空，并且在任何情况下都不得已经包含 `wsu:Timestamp`。
6. 如果 Body 尚无 `wsu:Id`，则为其分配 ID。
7. 创建包含 `Created`、`Expires` 和唯一 `wsu:Id` 的 UTC Timestamp。
8. 除非 `signature.key_info` 为 `none`，否则在 `wsse:BinarySecurityToken` 中嵌入 X.509 证书。
9. 使用 `signature.algorithm` 指定的算法分别计算 Body 和 Timestamp 的摘要。Body 中没有被任何元素名或属性名使用的命名空间声明会列入 `ec:InclusiveNamespaces` 的 `PrefixList`，从而同样受签名保护。
10. 对 canonicalized `ds:SignedInfo` 签名，替换发往上游的请求体、更新 `Content-Length`，并移除不再对应签名后请求体的摘要标头。

请求体会以 UTF-8 序列化。显式声明非 UTF-8 `charset` 的请求会被拒绝。

压缩的请求体必须先解压，例如使用 `request-decompress` 插件。残留的 Content-Encoding 如果不是 `identity`，则会被拒绝。

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

- APISIX 必须运行在 Linux 上，并且系统中提供 `libxml2.so.2`。已发布的 APISIX Debian、Ubuntu 和 Red Hat 镜像已包含此库。从源码构建的镜像（例如使用 [apisix-docker](https://github.com/apache/apisix-docker) 中的 `debian-dev/Dockerfile.local`）不包含此库，请在最终镜像中安装，例如执行 `apt-get install -y libxml2`。缺少此库时，APISIX 会在启动时记录 `soap-signer is unavailable and will reject requests`，插件会返回 `500 signing_error`。
- APISIX-Runtime 必须支持在 NGINX 读取请求体时强制执行 `request.max_body_bytes`。
- 证书和私钥必须为 PEM 编码，使用 RSA，并且属于同一密钥对。`rsa-sha256` 要求 RSA 密钥至少为 2048 位，`rsa-sha1` 要求至少为 1024 位。
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
| `soap.allow_existing_security_content` | boolean | 否 | `false` | 允许复用已有内容的 `wsse:Security` 标头，例如客户端提供的 `wsse:UsernameToken`。这些内容不受签名保护。为 `false` 时，被复用的标头必须为空。 |
| `timestamp.ttl_seconds` | integer | 否 | `300` | Timestamp 有效期，有效范围为 1 到 86400 秒。 |
| `request.methods` | array[string] | 否 | `["POST"]` | 要签名的请求方法。其他方法的请求保持不变并直接转发。 |
| `request.content_types` | array[string] | 否 | `["text/xml", "application/soap+xml", "application/xml"]` | 接受的媒体类型；显式声明非 UTF-8 `charset` 的请求会被拒绝。 |
| `request.require_consumer` | boolean | 否 | `true` | 只为已由认证插件关联到消费者的请求签名，其他请求返回 `401`。只有当路由已通过其他方式受到保护时才设置为 `false`。 |
| `request.max_body_bytes` | integer | 否 | `5242880` | 请求体最大字节数，有效范围为 1024 到 67108864。插件不会将限制提高到非零的 `nginx_config.http.client_max_body_size` 或路由上 `client-control` 配置的 `max_body_size` 之上，以较小值为准。 |

注意：schema 中定义了 `encrypt_fields = {"credentials.private_key"}`。只有启用 `apisix.data_encryption.enable_encrypt_fields` 并配置有效的 keyring 时，直接配置的私钥才会在 etcd 中加密；独立模式的 YAML 配置不会被加密。建议使用 [APISIX Secret](../terminology/secret.md) 引用，避免密钥材料保存在路由配置中。

### 签名算法

| 值 | SignatureMethod URI | DigestMethod URI | 最小 RSA 密钥长度 | 用途 |
| --- | --- | --- | --- | --- |
| `rsa-sha256` | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha256` | `http://www.w3.org/2001/04/xmlenc#sha256` | 2048 位 | 默认且推荐。 |
| `rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#sha1` | 1024 位 | 仅用于兼容旧版 WS-Security，可使用部分旧系统仍在使用的 1024 位密钥。 |

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

创建客户端用于认证的消费者，例如使用 [`key-auth`](key-auth.md)：

```shell
curl http://127.0.0.1:9180/apisix/admin/consumers \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "username": "signer_client",
  "plugins": {
    "key-auth": {"key": "signer-client-key"}
  }
}'
```

以下示例在要求 `key-auth` 的路由上启用 SOAP 版本自动检测和 RSA-SHA256：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-soap",
  "plugins": {
    "key-auth": {},
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
    "key-auth": {},
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
  -H "apikey: signer-client-key" \
  -H "Content-Type: application/soap+xml" \
  -d '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><Ping/></s:Body></s:Envelope>'
```

对于 SOAP 1.1，请使用 `Content-Type: text/xml` 和 SOAP 1.1 Envelope 命名空间：

```shell
curl http://127.0.0.1:9080/signed-soap \
  -H "apikey: signer-client-key" \
  -H "Content-Type: text/xml; charset=utf-8" \
  -d '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><Ping/></s:Body></s:Envelope>'
```

上游会收到包含已签名 WS-Security 标头的原始 SOAP 消息。请求方法未列入 `request.methods` 时，请求会保持不变并直接转发。没有有效密钥的请求会在到达本插件之前被 `key-auth` 拒绝。

## 错误响应

| HTTP 状态码 | 消息 | 原因 |
| --- | --- | --- |
| `401` | `unauthorized` | `request.require_consumer` 为 `true`，且请求未被认证插件关联到消费者。 |
| `400` | `empty_body` | 被选中的请求没有请求体。 |
| `400` | `invalid_soap` | XML 解析失败、Body 缺失或重复、Header 重复或位于 Body 之后、XML ID（`wsu:Id`、`xml:id` 和无命名空间的 `Id`）无效或重复、被复用的 `wsse:Security` 标头在 `soap.allow_existing_security_content` 为 `false` 时已有内容或已包含 `wsu:Timestamp`、存在 DTD/实体声明，或消息超出[限制](#限制)中列出的解析器限制。 |
| `400` | `not_soap` | 根元素不是受支持的 SOAP Envelope，或与 `soap.version` 不匹配。 |
| `400` | `already_signed` | 消息已包含 `ds:Signature`。 |
| `413` | `body_too_large` | 请求体超过生效的请求体大小限制（参见 `request.max_body_bytes`）。 |
| `415` | `unsupported_media_type` | Content-Type 缺失、重复、未列入 `request.content_types` 或声明了非 UTF-8 字符集；或者 Content-Encoding 重复或不是 `identity`。 |
| `500` | `credential_error` | Secret 解析失败、PEM 解析失败、密钥不是 RSA 或短于 `signature.algorithm` 要求的最小长度，或证书与私钥不匹配。 |
| `500` | `signing_error` | libxml2 不可用，或 ID 生成、canonicalization、摘要生成、签名或序列化失败。 |

不会向客户端返回详细的密码学信息或请求内容。

## 限制

- 仅对 SOAP Body 和生成的 Timestamp 签名；目前不能将自定义 SOAP 标头添加为签名目标。
- KeyInfo 仅支持 X.509 BinarySecurityToken 直接引用或省略；不支持其他 KeyInfo 格式。
- 不支持 Actor/Role 定向、thumbprint 引用、ECDSA、RSA-PSS 或替换已有签名。
- 签名前会缓冲整个请求体；此操作不是流式签名。
- 为了使解析时间保持线性，如果消息中某个元素的属性（包括命名空间声明）超过 256 个，或同时生效的命名空间声明超过 128 个，插件会拒绝该消息。实际消息远低于这些限制。
- 当 `soap.allow_existing_security_content` 为 `true` 时，被复用的 `wsse:Security` 标头中已有的内容（例如客户端提供的 `wsse:UsernameToken`）不受签名保护。服务不得将此类内容视为由 APISIX 担保。
- Exclusive canonicalization 只输出元素名和属性名使用的命名空间声明。如果 Body 中的某个前缀只出现在文本或属性值中（例如 `xsi:type="ns:Type"` 中的 `ns`），插件会将其列入 Body 引用的 `ec:InclusiveNamespaces` `PrefixList`，因此修改其绑定会使签名失效。验证方必须支持该参数，它属于 Exclusive XML Canonicalization 规范的一部分。
- 插件不会强制检查签名证书的有效期。当 APISIX 加载已过期或尚未生效的证书时会记录警告，因为验证方会拒绝此类签名。

## 故障排查

- 如果 APISIX 记录 `soap-signer is unavailable and will reject requests: libxml2 is not available`，并且请求返回 `500 signing_error`，请在 APISIX 镜像或主机中安装 `libxml2` 并重启 APISIX。
- 如果服务报告摘要不匹配，请确认没有优先级更低的插件或上游代理修改 Body、Timestamp、命名空间声明或 ID。
- 如果 APISIX 返回 `not_soap`，请根据 Envelope 命名空间检查 `soap.version`，不要只依赖 Content-Type。
- 如果 APISIX 返回 `credential_error`，请检查 Secret URI、PEM 边界、RSA 密钥类型和长度（`rsa-sha256` 至少 2048 位，`rsa-sha1` 至少 1024 位）以及证书与私钥是否匹配。
- 如果旧版服务拒绝 RSA-SHA256，请先将其预期算法 URI 与上表比较，再考虑启用 `rsa-sha1`。
- 如果服务拒绝 `mustUnderstand`，请确认它要求 SOAP 1.1 的数字值还是 SOAP 1.2 的布尔值。

## 删除插件

从路由插件配置中移除 `soap-signer`，并通过 Admin API 更新路由。APISIX 无需重启即可应用此更改。
