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

## 目录

- [目录](#目录)
- [检查外部依赖](#检查外部依赖)
- [插件命名与配置](#插件命名与配置)
- [配置描述与校验](#配置描述与校验)
- [确定执行阶段](#确定执行阶段)
- [编写执行逻辑](#编写执行逻辑)
  - [conf 参数](#conf-参数)
  - [ctx 参数](#ctx-参数)
- [编写测试用例](#编写测试用例)
  - [附上 test-nginx 执行流程](#附上-test-nginx-执行流程)
  - [注册公共接口](#注册公共接口)
  - [注册控制接口](#注册控制接口)

## 检查外部依赖

如果你的插件，涉及到一些外部的依赖和三方库，请首先检查一下依赖项的内容。 如果插件需要用到共享内存，需要在[自定义 Nginx 配置](./customize-nginx-configuration.md)，例如：

```yaml
# put this in config.yaml:
nginx_config:
    http_configuration_snippet: |
        # for openid-connect plugin
        lua_shared_dict discovery             1m; # cache for discovery metadata documents
        lua_shared_dict jwks                  1m; # cache for JWKs
        lua_shared_dict introspection        10m; # cache for JWT verification results
```

插件本身提供了 init 方法。方便插件加载后做初始化动作。

注：如果部分插件的功能实现，需要在 Nginx 初始化启动，则可能需要在 __apisix/init.lua__ 文件的初始化方法 http_init 中添加逻辑，并且
可能需要在 __apisix/cli/ngx_tpl.lua__ 文件中，对 Nginx 配置文件生成的部分，添加一些你需要的处理。但是这样容易对全局产生影响，根据现有的
插件机制，**我们不建议这样做，除非你已经对代码完全掌握**。

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

注：新插件的优先级（ priority 属性 ）不能与现有插件的优先级相同，您可以使用 [control API](../../en/latest/control-api.md#get-v1schema) 的 `/v1/schema` 方法查看所有插件的优先级。另外，同一个阶段里面，优先级( priority )值大的插件，会优先执行，比如 `example-plugin` 的优先级是 0 ，`ip-restriction` 的优先级是 3000 ，所以在每个阶段，会先执行 `ip-restriction` 插件，再去执行 `example-plugin` 插件。这里的“阶段”的定义，参见后续的[确定执行阶段](#确定执行阶段)这一节。对于你的插件，建议采用 1 到 99 之间的优先级。

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

定义插件的配置项，以及对应的 [JSON Schema](https://json-schema.org) 描述，并完成对 JSON 的校验，这样方便对配置的数据规
格进行验证，以确保数据的完整性以及程序的健壮性。同样，我们以 example-plugin 插件为例，看看他的配置数据：

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

另外，如果插件需要使用一些元数据，可以定义插件的 `metadata_schema` ，然后就可以通过 `admin api` 动态的管理这些元数据了。如：

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

## 确定执行阶段

根据业务功能，确定你的插件需要在哪个阶段执行。 key-auth 是一个认证插件，所以需要在 rewrite 阶段执行。在 APISIX，只有认证逻辑可以在 rewrite 阶段里面完成，其他需要在代理到上游之前执行的逻辑都是在 access 阶段完成的。

**注意：我们不能在 rewrite 和 access 阶段调用 `ngx.exit` 或者 `core.respond.exit`。如果确实需要退出，只需要 return 状态码和正文，插件引擎将使用返回的状态码和正文进行退出。[例子](https://github.com/apache/apisix/blob/35269581e21473e1a27b11cceca6f773cad0192a/apisix/plugins/limit-count.lua#L177)**

## 编写执行逻辑

在对应的阶段方法里编写功能的逻辑代码，在阶段方法中具有 `conf` 和 `ctx` 两个参数，以 `limit-conn` 插件配置为例。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
            "39.97.63.215:80": 1
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

- 程序代码： Nginx location 的配置内容
- 输入： http 的 request 信息
- 输出检查： status ，header ，body ，error_log 检查

这里请求 __/t__ ，经过配置文件 __location__ ，调用 __content_by_lua_block__ 指令完成 lua 的脚本，最终返回。
用例的断言是 response_body 返回 "done"，__no_error_log__ 表示会对 Nginx 的 error.log 检查，
必须没有 ERROR 级别的记录。

### 附上 test-nginx 执行流程

根据我们在 Makefile 里配置的 PATH，和每一个 __.t__ 文件最前面的一些配置项，框架会组装成一个完整的 nginx.conf 文件，
__t/servroot__ 会被当成 Nginx 的工作目录，启动 Nginx 实例。根据测试用例提供的信息，发起 http 请求并检查 http 的返回项，
包括 http status，http response header， http response body 等。

### 注册公共接口

插件可以注册暴露给公网的接口。以 jwt-auth 插件为例，这个插件为了让客户端能够签名，注册了 `GET /apisix/plugin/jwt/sign` 这个接口:

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

注意注册的接口会暴露到外网。
你可能需要使用 [interceptors](plugin-interceptors.md) 来保护它。

### 注册控制接口

如果你只想暴露 API 到 localhost 或内网，你可以通过 [Control API](../../en/latest/control-api.md) 来暴露它。

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

如果你没有改过默认的 control API 配置，这个插件暴露的 `GET /v1/plugin/example-plugin/hello` API 只有通过 `127.0.0.1` 才能访问它。
