---
title: 插件开发
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

此文档是关于 lua 语言的插件开发，其他语言请看：[external plugin](./external-plugin.md)。

## 插件放置路径

Apache APISIX 提供了两种方式来添加新的功能。

1. 修改 Apache APISIX 的源代码并重新发布 (不推荐)。
2. 配置 `extra_lua_path` 和 `extra_lua_cpath` 在 `conf/config.yaml` 以加载你自己的代码文件。你应该给自己的代码文件起一个不包含在原来库中的名字，而不是使用相同名称的代码文件，但是如果有需要，你可以使用这种方式覆盖内置的代码文件。

比如，你可以创建一个目录目录结构，像下面这样：

```
├── example
│   └── apisix
│       ├── plugins
│       │   └── 3rd-party.lua
│       └── stream
│           └── plugins
│               └── 3rd-party.lua
```

:::note

如果你需要自定义插件的目录，请在该目录下创建 `/apisix/plugins` 的子目录。

:::

接着，在 `conf/config.yaml` 文件中添加如下的配置：

```yaml
apisix:
    ...
    extra_lua_path: "/path/to/example/?.lua"
```

现在使用 `require "apisix.plugins.3rd-party"` 会加载你自己的插件，比如 `require "apisix.plugins.jwt-auth"`会加载 `jwt-auth` 插件。

可能你会想覆盖一个文件中的函数，你可以在 `conf/config.yaml` 文件中配置 `lua_module_hook` 来使你的 hook 生效。

你的配置可以像下面这样：

```yaml
apisix:
    ...
    extra_lua_path: "/path/to/example/?.lua"
    lua_module_hook: "my_hook"
```

当 APISIX 启动的时候，`example/my_hook.lua` 就会被加载，这时你可以使用这个钩子在 APISIX 中来全局替换掉一个方法。
这个例子：[my_hook.lua](https://github.com/apache/apisix/blob/master/example/my_hook.lua) 可以在项目的 `example` 路径下被找到。

## 检查外部依赖

如果你的插件，涉及到一些外部的依赖和三方库，请首先检查一下依赖项的内容。如果插件需要用到共享内存，需要在 [自定义 Nginx 配置](./customize-nginx-configuration.md)，例如：

```yaml
# put this in config.yaml:
nginx_config:
    http_configuration_snippet: |
        # for openid-connect plugin
        lua_shared_dict discovery             1m; # cache for discovery metadata documents
        lua_shared_dict jwks                  1m; # cache for JWKs
        lua_shared_dict introspection        10m; # cache for JWT verification results
```

插件本身提供了 init 方法。方便插件加载后做初始化动作。如果你需要清理初始化动作创建出来的内容，你可以在对应的 destroy 方法里完成这一操作。

注：如果部分插件的功能实现，需要在 Nginx 初始化启动，则可能需要在 __apisix/init.lua__ 文件的初始化方法 http_init 中添加逻辑，并且可能需要在 __apisix/cli/ngx_tpl.lua__ 文件中，对 Nginx 配置文件生成的部分，添加一些你需要的处理。但是这样容易对全局产生影响，根据现有的插件机制，**我们不建议这样做，除非你已经对代码完全掌握**。

## 插件命名，优先级和其他

给插件取一个很棒的名字，确定插件的加载优先级，然后在 __conf/config.yaml__ 文件中添加上你的插件名。例如 example-plugin 这个插件，
需要在代码里指定插件名称（名称是插件的唯一标识，不可重名），在 __apisix/plugins/example-plugin.lua__ 文件中可以看到：

```lua
local plugin_name = "example-plugin"

local _M = {
    version = 0.1,
    priority = 0,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}
```

注：新插件的优先级（priority 属性）不能与现有插件的优先级相同，您可以使用 [control API](./control-api.md#get-v1schema) 的 `/v1/schema` 方法查看所有插件的优先级。另外，同一个阶段里面，优先级 ( priority ) 值大的插件，会优先执行，比如 `example-plugin` 的优先级是 0，`ip-restriction` 的优先级是 3000，所以在每个阶段，会先执行 `ip-restriction` 插件，再去执行 `example-plugin` 插件。这里的“阶段”的定义，参见后续的 [确定执行阶段](#确定执行阶段) 这一节。对于你的插件，建议采用 1 到 99 之间的优先级。

在 __conf/config-default.yaml__ 配置文件中，列出了启用的插件（都是以插件名指定的）：

```yaml
plugins:                          # plugin list
  - limit-req
  - limit-count
  - limit-conn
  - key-auth
  - prometheus
  - node-status
  - jwt-auth
  - zipkin
  - ip-restriction
  - grpc-transcode
  - serverless-pre-function
  - serverless-post-function
  - openid-connect
  - proxy-rewrite
  - redirect
  ...
```

注：先后顺序与执行顺序无关。

特别需要注意的是，如果你的插件有新建自己的代码目录，那么就需要修改 Makefile 文件，新增创建文件夹的操作，比如：

```
$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/skywalking
$(INSTALL) apisix/plugins/skywalking/*.lua $(INST_LUADIR)/apisix/plugins/skywalking/
```

`_M` 中还有其他字段会影响到插件的行为。

```lua
local _M = {
    ...
    type = 'auth',
    run_policy = 'prefer_route',
}
```

`run_policy` 字段可以用来控制插件执行。当这个字段设置成 `prefer_route` 时，且该插件同时配置在全局和路由级别，那么只有路由级别的配置生效。

如果你的插件需要跟 `consumer` 一起使用，需要把 `type` 设置成 `auth`。详情见下文。

## 配置描述与校验

定义插件的配置项，以及对应的 [JSON Schema](https://json-schema.org) 描述，并完成对 JSON 的校验，这样方便对配置的数据规格进行验证，以确保数据的完整性以及程序的健壮性。同样，我们以 example-plugin 插件为例，看看他的配置数据：

```json
{
  "example-plugin": {
    "i": 1,
    "s": "s",
    "t": [1]
  }
}
```

我们看下他的 Schema 描述：

```lua
local schema = {
    type = "object",
    properties = {
        i = {type = "number", minimum = 0},
        s = {type = "string"},
        t = {type = "array", minItems = 1},
        ip = {type = "string"},
        port = {type = "integer"},
    },
    required = {"i"},
}
```

这个 schema 定义了一个非负数 `i`，字符串 `s`，非空数组 `t`，和 `ip` 跟 `port`。只有 `i` 是必需的。

同时，需要实现 __check_schema(conf)__ 方法，完成配置参数的合法性校验。

```lua
function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end
```

注：项目已经提供了 __core.schema.check__ 公共方法，直接使用即可完成配置参数校验。

另外，如果插件需要使用一些元数据，可以定义插件的 `metadata_schema` ，然后就可以通过 `Admin API` 动态的管理这些元数据了。如：

```lua
local metadata_schema = {
    type = "object",
    properties = {
        ikey = {type = "number", minimum = 0},
        skey = {type = "string"},
    },
    required = {"ikey", "skey"},
}

local plugin_name = "example-plugin"

local _M = {
    version = 0.1,
    priority = 0,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}
```

你可能之前见过 key-auth 这个插件在它的模块定义时设置了 `type = 'auth'`。
当一个插件设置 `type = 'auth'`，说明它是个认证插件。

认证插件需要在执行后选择对应的 consumer。举个例子，在 key-auth 插件中，它通过 `apikey` 请求头获取对应的 consumer，然后通过 `consumer.attach_consumer` 设置它。

为了跟 `consumer` 资源一起使用，认证插件需要提供一个 `consumer_schema` 来检验 `consumer` 资源的 `plugins` 属性里面的配置。

下面是 key-auth 插件的 consumer 配置：

```json
{
  "username": "Joe",
  "plugins": {
    "key-auth": {
      "key": "Joe's key"
    }
  }
}
```

你在创建 [Consumer](https://github.com/apache/apisix/blob/master/docs/zh/latest/admin-api.md#consumer) 时会用到它。

为了检验这个配置，这个插件使用了如下的 schema:

```lua
local consumer_schema = {
    type = "object",
    properties = {
        key = {type = "string"},
    },
    required = {"key"},
}
```

注意 key-auth 的 __check_schema(conf)__ 方法和 example-plugin 的同名方法的区别：

```lua
-- key-auth
function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end
end
```

```lua
-- example-plugin
function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end
```

### 加密存储字段

指定参数需要被加密存储（需要 APISIX 版本不小于 3.1）

有些插件需要将参数加密存储，比如 `basic-auth` 插件的 `password` 参数。这个插件需要在 `schema` 中指定哪些参数需要被加密存储。

```lua
encrypt_fields = {"password"}
```

如果是嵌套的参数，比如 `error-log-logger` 插件的 `clickhouse.password` 参数，需要用 `.` 来分隔：

```lua
encrypt_fields = {"clickhouse.password"}
```

目前还不支持：

1. 两层以上的嵌套
2. 数组中的字段

通过在 `schema` 中指定 `encrypt_fields = {"password"}`，可以将参数加密存储。APISIX 将提供以下功能：

- 通过 `Admin API` 来新增和更新资源时，对于 `encrypt_fields` 中声明的参数，APISIX 会自动加密存储在 etcd 中
- 通过 `Admin API` 来获取资源时，以及在运行插件时，对于 `encrypt_fields` 中声明的参数，APISIX 会自动解密

如何开启该功能？

在 `config.yaml` 中开启 `data_encryption`：

```yaml
apisix:
    data_encryption:
    enable: true
    keyring:
        - edd1c9f0985e76a2
        - qeddd145sfvddff4
```

`keyring` 是一个数组，可以指定多个 key，APISIX 会按照 keyring 中 key 的顺序，依次尝试用 key 来解密数据（只对在 `encrypt_fields` 声明的参数）。如果解密失败，会尝试下一个 key，直到解密成功。

如果 `keyring` 中的 key 都无法解密数据，则使用原始数据。

## 确定执行阶段

根据业务功能，确定你的插件需要在哪个阶段执行。key-auth 是一个认证插件，所以需要在 rewrite 阶段执行。在 APISIX，只有认证逻辑可以在 rewrite 阶段里面完成，其他需要在代理到上游之前执行的逻辑都是在 access 阶段完成的。

**注意：我们不能在 rewrite 和 access 阶段调用 `ngx.exit`、`ngx.redirect` 或者 `core.respond.exit`。如果确实需要退出，只需要 return 状态码和正文，插件引擎将使用返回的状态码和正文进行退出。[例子](https://github.com/apache/apisix/blob/35269581e21473e1a27b11cceca6f773cad0192a/apisix/plugins/limit-count.lua#L177)**

### APISIX 的自定义阶段

除了 OpenResty 的阶段，我们还提供额外的阶段来满足特定的目的：

* `delayed_body_filter`

```lua
function _M.delayed_body_filter(conf, ctx)
    -- delayed_body_filter 在 body_filter 之后被调用。
    -- 它被 tracing 类型插件用来在 body_filter 之后立即结束 span。
end
```

## 编写执行逻辑

在对应的阶段方法里编写功能的逻辑代码，在阶段方法中具有 `conf` 和 `ctx` 两个参数，以 `limit-conn` 插件配置为例。

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "id": 1,
    "plugins": {
        "limit-conn": {
            "conn": 1,
            "burst": 0,
            "default_conn_delay": 0.1,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

### conf 参数

`conf` 参数是插件的相关配置信息，您可以通过 `core.log.warn(core.json.encode(conf))` 将其输出到 `error.log` 中进行查看，如下所示：

```lua
function _M.access(conf, ctx)
    core.log.warn(core.json.encode(conf))
    ......
end
```

conf:

```json
{
  "rejected_code": 503,
  "burst": 0,
  "default_conn_delay": 0.1,
  "conn": 1,
  "key": "remote_addr"
}
```

### ctx 参数

`ctx` 参数缓存了请求相关的数据信息，您可以通过 `core.log.warn(core.json.encode(ctx, true))` 将其输出到 `error.log` 中进行查看，如下所示：

```lua
function _M.access(conf, ctx)
    core.log.warn(core.json.encode(ctx, true))
    ......
end
```

## 注册公共接口

插件可以注册暴露给公网的接口。以 jwt-auth 插件为例，这个插件为了让客户端能够签名，注册了 `GET /apisix/plugin/jwt/sign` 这个接口：

```lua
local function gen_token()
    -- ...
end

function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/plugin/jwt/sign",
            handler = gen_token,
        }
    }
end
```

注意，注册的接口将不会默认暴露，需要使用[public-api 插件](../../en/latest/plugins/public-api.md)来暴露它。

## 注册控制接口

如果你只想暴露 API 到 localhost 或内网，你可以通过 [Control API](./control-api.md) 来暴露它。

Take a look at example-plugin plugin:

```lua
local function hello()
    local args = ngx.req.get_uri_args()
    if args["json"] then
        return 200, {msg = "world"}
    else
        return 200, "world\n"
    end
end


function _M.control_api()
    return {
        {
            methods = {"GET"},
            uris = {"/v1/plugin/example-plugin/hello"},
            handler = hello,
        }
    }
end
```

如果你没有改过默认的 control API 配置，这个插件暴露的 `GET /v1/plugin/example-plugin/hello` API 只有通过 `127.0.0.1` 才能访问它。通过以下命令进行测试：

```shell
curl -i -X GET "http://127.0.0.1:9090/v1/plugin/example-plugin/hello"
```

[查看更多有关 control API 介绍](./control-api.md)

## 注册自定义变量

我们可以在 APISIX 的许多地方使用变量。例如，在 http-logger 中自定义日志格式，用它作为 `limit-*` 插件的键。在某些情况下，内置的变量是不够的。因此，APISIX 允许开发者在全局范围内注册他们的变量，并将它们作为普通的内置变量使用。

例如，让我们注册一个叫做 `a6_labels_zone` 的变量来获取路由中 `zone` 标签的值。

```
local core = require "apisix.core"

core.ctx.register_var("a6_labels_zone", function(ctx)
    local route = ctx.matched_route and ctx.matched_route.value
    if route and route.labels then
        return route.labels.zone
    end
    return nil
end)
```

此后，任何对 `$a6_labels_zone` 的获取操作都会调用注册的获取器来获取数值。

注意，自定义变量不能用于依赖 Nginx 指令的功能，如 `access_log_format`。

## 编写测试用例

针对功能，完善各种维度的测试用例，对插件做个全方位的测试吧！插件的测试用例，都在 __t/plugin__ 目录下，可以前去了解。
项目测试框架采用的 [****test-nginx****](https://github.com/openresty/test-nginx) 。
一个测试用例 __.t__ 文件，通常用 \__DATA\__ 分割成 序言部分 和 数据部分。这里我们简单介绍下数据部分，
也就是真正测试用例的部分，仍然以 key-auth 插件为例：

```perl
=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.key-auth")
            local ok, err = plugin.check_schema({key = 'test-key'}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]
```

一个测试用例主要有三部分内容：

- 程序代码：Nginx location 的配置内容
- 输入：http 的 request 信息
- 输出检查：status，header，body，error_log 检查

这里请求 __/t__，经过配置文件 __location__，调用 __content_by_lua_block__ 指令完成 lua 的脚本，最终返回。
用例的断言是 response_body 返回 "done"，__no_error_log__ 表示会对 Nginx 的 error.log 检查，
必须没有 ERROR 级别的记录。

### 附上 test-nginx 执行流程

根据我们在 Makefile 里配置的 PATH，和每一个 __.t__ 文件最前面的一些配置项，框架会组装成一个完整的 nginx.conf 文件，
__t/servroot__ 会被当成 Nginx 的工作目录，启动 Nginx 实例。根据测试用例提供的信息，发起 http 请求并检查 http 的返回项，
包括 http status，http response header，http response body 等。
