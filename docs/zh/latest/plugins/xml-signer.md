---
title: xml-signer
keywords:
  - Apache APISIX
  - API 网关
  - 插件
  - XMLDSig
  - XML 签名
description: xml-signer 插件为 XML 请求体添加 enveloped XML 数字签名。
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

`xml-signer` 插件会在请求转发到上游之前，为 XML 请求体添加 enveloped [XML 数字签名](https://www.w3.org/TR/xmldsig-core1/)。签名覆盖整个 XML 文档，并通过 enveloped-signature 转换排除新生成的 `ds:Signature` 元素。

插件支持日常使用的 RSA-SHA256，以及用于兼容旧系统的 RSA-SHA1；使用不带注释的 exclusive XML canonicalization。默认情况下，插件会在 `ds:KeyInfo` 中包含配置的 X.509 证书。如果验证方通过带外方式获取证书，也可以省略该元素。

不要在同一个路由中将本插件与其他请求签名插件组合使用。本插件会拒绝已经包含 XML 签名的文档。

:::caution

插件会使用配置的私钥为到达它的每个格式正确的 XML 文档签名。默认情况下（`request.require_consumer` 为 `true`），插件只为已由认证插件（例如 [`key-auth`](key-auth.md) 或 [`jwt-auth`](jwt-auth.md)）关联到消费者的请求签名，否则返回 `401`。认证插件会在 `xml-signer` 之前执行。认证插件上配置的 `anonymous_consumer` 同样满足此检查，因此不要在签名路由上配置匿名消费者。只有当路由已通过其他方式受到保护（例如 mTLS、`ip-restriction` 或 `forward-auth`）时，才应将 `request.require_consumer` 设置为 `false`。

:::

## 工作原理

匹配的请求在 rewrite 阶段会依次执行以下操作：

1. 当 `request.require_consumer` 为 `true` 时，如果请求未被认证插件关联到消费者，则返回 `401`。
2. 将请求体缓冲到 `request.max_body_bytes` 限制以内。
3. 在禁用外部网络访问的情况下解析 XML。
4. 拒绝 DTD、实体声明以及已包含 `ds:Signature` 元素的文档。
5. 对文档执行 exclusive XML canonicalization。没有被任何元素名或属性名使用的命名空间声明会列入 `ec:InclusiveNamespaces` 的 `PrefixList`，从而同样受签名保护。
6. 使用 `signature.algorithm` 指定的算法计算引用摘要。
7. 在文档根元素下创建 enveloped `ds:Signature`。
8. 除非 `signature.key_info` 为 `none`，否则添加 X.509 `ds:KeyInfo`。
9. 对 `ds:SignedInfo` 执行 canonicalization，并使用配置的 RSA 私钥签名。
10. 替换发往上游的请求体、更新 `Content-Length`，并移除不再对应签名后请求体的摘要标头。

签名后的请求体会以 UTF-8 序列化，因此缩进、引号风格等无关格式可能与原请求不同。显式声明非 UTF-8 `charset` 的请求会被拒绝。

压缩的请求体必须先解压，例如使用 `request-decompress` 插件。残留的 Content-Encoding 如果不是 `identity`，则会被拒绝。

生成的签名结构如下：

```xml
<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
  <ds:SignedInfo>
    <ds:CanonicalizationMethod
      Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
    <ds:SignatureMethod Algorithm="..."/>
    <ds:Reference URI="">
      <ds:Transforms>
        <ds:Transform
          Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
        <ds:Transform
          Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
      </ds:Transforms>
      <ds:DigestMethod Algorithm="..."/>
      <ds:DigestValue>...</ds:DigestValue>
    </ds:Reference>
  </ds:SignedInfo>
  <ds:SignatureValue>...</ds:SignatureValue>
  <ds:KeyInfo>
    <ds:X509Data><ds:X509Certificate>...</ds:X509Certificate></ds:X509Data>
  </ds:KeyInfo>
</ds:Signature>
```

## 要求

- APISIX 必须运行在 Linux 上，并且系统中提供 `libxml2.so.2`。已发布的 APISIX Debian、Ubuntu 和 Red Hat 镜像已包含此库。从源码构建的镜像（例如使用 [apisix-docker](https://github.com/apache/apisix-docker) 中的 `debian-dev/Dockerfile.local`）不包含此库，请在最终镜像中安装，例如执行 `apt-get install -y libxml2`。缺少此库时，APISIX 会在启动时记录 `xml-signer is unavailable and will reject requests`，插件会返回 `500 signing_error`。
- 证书和私钥必须为 PEM 编码，使用 RSA，并且属于同一密钥对。`rsa-sha256` 要求 RSA 密钥至少为 2048 位，`rsa-sha1` 要求至少为 1024 位。
- 上游验证方必须支持 exclusive XML canonicalization。
- 请将插件配置在所有其他请求体修改插件之后。此插件之后对请求体的任何修改都会使签名失效。

## 属性

| 名称 | 类型 | 必选 | 默认值 | 描述 |
| --- | --- | --- | --- | --- |
| `credentials` | object | 是 | | 签名凭据。 |
| `credentials.certificate` | string | 是 | | PEM 编码的 X.509 证书或 APISIX Secret 引用。 |
| `credentials.private_key` | string | 是 | | PEM 编码的 RSA 私钥或 APISIX Secret 引用。 |
| `signature` | object | 否 | `{}` | 签名配置。 |
| `signature.algorithm` | string | 否 | `rsa-sha256` | 签名和引用摘要算法。可选值为 `rsa-sha256` 和 `rsa-sha1`。 |
| `signature.key_info` | string | 否 | `x509_data` | 签名中包含的密钥信息。使用 `x509_data` 嵌入证书，或使用 `none` 省略 `ds:KeyInfo`。 |
| `request.methods` | array[string] | 否 | `["POST"]` | 要签名的请求方法。其他方法的请求保持不变并直接转发。 |
| `request.content_types` | array[string] | 否 | `["application/xml", "text/xml"]` | 接受的媒体类型；会忽略其他参数，但会拒绝显式声明非 UTF-8 `charset` 的请求。 |
| `request.require_consumer` | boolean | 否 | `true` | 只为已由认证插件关联到消费者的请求签名，其他请求返回 `401`。只有当路由已通过其他方式受到保护时才设置为 `false`。 |
| `request.max_body_bytes` | integer | 否 | `5242880` | 请求体最大字节数，有效范围为 1024 到 67108864。插件不会将限制提高到非零的 `nginx_config.http.client_max_body_size` 或路由上 `client-control` 配置的 `max_body_size` 之上，以较小值为准。 |

注意：schema 中定义了 `encrypt_fields = {"credentials.private_key"}`。只有启用 `apisix.data_encryption.enable_encrypt_fields` 并配置有效的 keyring 时，直接配置的私钥才会在 etcd 中加密；独立模式的 YAML 配置不会被加密。建议使用 [APISIX Secret](../terminology/secret.md) 引用，避免密钥材料保存在路由配置中。

### 签名算法

| 值 | SignatureMethod URI | DigestMethod URI | 最小 RSA 密钥长度 | 用途 |
| --- | --- | --- | --- | --- |
| `rsa-sha256` | `http://www.w3.org/2001/04/xmldsig-more#rsa-sha256` | `http://www.w3.org/2001/04/xmlenc#sha256` | 2048 位 | 默认且推荐。 |
| `rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#rsa-sha1` | `http://www.w3.org/2000/09/xmldsig#sha1` | 1024 位 | 仅用于兼容旧系统，可使用部分旧系统仍在使用的 1024 位密钥。 |

:::warning

SHA-1 在密码学上较弱。只有无法验证 RSA-SHA256 签名的旧版上游系统才应启用该算法。APISIX 每次使用 `rsa-sha1` 对请求签名时都会记录警告。请使用 TLS、限制网络访问、缩短凭据轮换周期，并制定迁移到 RSA-SHA256 的计划。

:::

## 配置凭据

可以直接配置 PEM 值，但使用 Secret 引用可避免私钥材料出现在路由配置中。引用格式如下：

```text
$secret://<manager>/<configuration-id>/<key-path>
```

例如，创建名为 `signing` 的 APISIX Vault Secret 资源后，可以按如下方式引用证书和私钥：

```json
{
  "credentials": {
    "certificate": "$secret://vault/signing/xml/certificate",
    "private_key": "$secret://vault/signing/xml/private-key"
  }
}
```

APISIX 会在插件执行前解析引用。解析后的凭据会在每个 worker 中按解析值的指纹缓存。Secret 缓存返回轮换后的 PEM 值时，插件会解析并使用新的密钥对，无需重启 APISIX worker。

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

以下示例在要求 `key-auth` 的路由上启用 RSA-SHA256 签名：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-xml",
  "plugins": {
    "key-auth": {},
    "xml-signer": {
      "credentials": {
        "certificate": "$secret://vault/signing/xml/certificate",
        "private_key": "$secret://vault/signing/xml/private-key"
      },
      "signature": {"algorithm": "rsa-sha256"},
      "request": {"max_body_bytes": 5242880}
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {"127.0.0.1:9001": 1}
  }
}'
```

若要与只接受 SHA-1 的旧系统通信，请修改签名配置：

```json
{
  "signature": {"algorithm": "rsa-sha1"}
}
```

无需修改其他配置。`SignatureMethod` 和 `DigestMethod` 会一起切换，避免生成混用算法的签名。

## 禁用 KeyInfo

如果上游验证方已配置签名证书且要求签名中不包含 `ds:KeyInfo`，请将 `signature.key_info` 设为 `none`。插件仍要求同时提供两种凭据：私钥用于签名，证书用于验证配置的密钥对是否匹配。

以下 Admin API 请求会创建不输出 `ds:KeyInfo` 的路由：

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/2 \
  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "uri": "/signed-xml-without-key-info",
  "plugins": {
    "key-auth": {},
    "xml-signer": {
      "credentials": {
        "certificate": "$secret://vault/signing/xml/certificate",
        "private_key": "$secret://vault/signing/xml/private-key"
      },
      "signature": {
        "algorithm": "rsa-sha256",
        "key_info": "none"
      }
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {"127.0.0.1:9001": 1}
  }
}'
```

生成的 XML 仍包含 `ds:SignedInfo`、`ds:SignatureValue` 和文档摘要，但不包含 `ds:KeyInfo` 或嵌入的证书。上游必须通过自身配置选择可信的验证证书。

## 使用示例

发送 XML 请求：

```shell
curl http://127.0.0.1:9080/signed-xml \
  -H "apikey: signer-client-key" \
  -H "Content-Type: application/xml" \
  -d '<order xmlns="urn:example"><id>42</id></order>'
```

上游会收到一个在文档根元素下带有 enveloped `ds:Signature` 的请求体。请求方法未列入 `request.methods` 时，请求会保持不变并直接转发。没有有效密钥的请求会在到达本插件之前被 `key-auth` 拒绝。

## 错误响应

| HTTP 状态码 | 消息 | 原因 |
| --- | --- | --- |
| `401` | `unauthorized` | `request.require_consumer` 为 `true`，且请求未被认证插件关联到消费者。 |
| `400` | `empty_body` | 被选中的请求没有请求体。 |
| `400` | `invalid_xml` | XML 解析失败、文档的命名空间格式不正确（例如使用了未声明的前缀）、文档没有根元素、存在 DTD/实体声明，或文档超出[限制](#限制)中列出的解析器限制。 |
| `400` | `already_signed` | 文档已包含 `ds:Signature`。 |
| `413` | `body_too_large` | 请求体超过生效的请求体大小限制（参见 `request.max_body_bytes`）。 |
| `415` | `unsupported_media_type` | Content-Type 缺失、重复、未列入 `request.content_types` 或声明了非 UTF-8 字符集；或者 Content-Encoding 重复或不是 `identity`。 |
| `500` | `credential_error` | Secret 解析失败、PEM 解析失败、密钥不是 RSA 或短于 `signature.algorithm` 要求的最小长度，或证书与私钥不匹配。 |
| `500` | `signing_error` | libxml2 不可用，或 canonicalization、摘要生成、签名或序列化失败。 |

不会向客户端返回详细的密码学信息或请求内容。

## 限制

- 仅支持使用 `Reference URI=""` 的 enveloped 全文档签名。
- `KeyInfo` 仅支持包含 X.509 数据或省略；不支持其他 KeyInfo 格式。
- 不支持分离式签名、XPath 转换、ECDSA、RSA-PSS 或对已签名文档重新签名。
- 签名前会将整个请求体缓冲到内存或临时请求体文件中；此操作不是流式转换。
- 为了使解析时间保持线性，如果文档中某个元素的属性（包括命名空间声明）超过 256 个，或同时生效的命名空间声明超过 128 个，插件会拒绝该文档。实际文档远低于这些限制。
- Exclusive canonicalization 只输出元素名和属性名使用的命名空间声明。如果文档声明的某个前缀只出现在文本或属性值中（例如 `xsi:type="ns:Type"` 中的 `ns`），插件会将其列入 canonicalization 转换的 `ec:InclusiveNamespaces` `PrefixList`，因此修改其绑定会使签名失效。验证方必须支持该参数，它属于 Exclusive XML Canonicalization 规范的一部分。
- 插件不会强制检查签名证书的有效期。当 APISIX 加载已过期或尚未生效的证书时会记录警告，因为验证方会拒绝此类签名。

## 故障排查

- 如果 APISIX 记录 `xml-signer is unavailable and will reject requests: libxml2 is not available`，并且请求返回 `500 signing_error`，请在 APISIX 镜像或主机中安装 `libxml2` 并重启 APISIX。
- 如果上游报告摘要不匹配，请确认没有优先级低于 `xml-signer` 的插件在其后修改请求体。
- 如果 APISIX 返回 `credential_error`，请检查 Secret URI、PEM 边界、RSA 密钥类型和长度（`rsa-sha256` 至少 2048 位，`rsa-sha1` 至少 1024 位）以及证书与私钥是否匹配。
- 如果旧版验证方拒绝签名，请将其要求的算法 URI 与上表比较，并确认它支持 exclusive C14N。
- 如果请求返回 `415`，请在 `request.content_types` 中加入 XML 媒体类型，或修正客户端的 Content-Type 标头。

## 删除插件

从路由插件配置中移除 `xml-signer`，并通过 Admin API 更新路由。APISIX 无需重启即可应用此更改。
