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
[English](../plugin-develop.md)

# 目录

- [**检查外部依赖**](#检查外部依赖)
- [**插件命名与配置**](#插件命名与配置)
- [**配置描述与校验**](#配置描述与校验)
- [**确定执行阶段**](#确定执行阶段)
- [**编写执行逻辑**](#编写执行逻辑)
- [**编写测试用例**](#编写测试用例)

## 检查外部依赖

如果你的插件，涉及到一些外部的依赖和三方库，请首先检查一下依赖项的内容。 如果插件需要用到共享内存，需要在 __bin/apisix__ 文
件里面进行申明，例如：

```nginx
    lua_shared_dict plugin-limit-req     10m;
    lua_shared_dict plugin-limit-count   10m;
    lua_shared_dict prometheus-metrics   10m;
    lua_shared_dict plugin-limit-conn    10m;
    lua_shared_dict upstream-healthcheck 10m;
    lua_shared_dict worker-events        10m;

    # for openid-connect plugin
    lua_shared_dict discovery             1m; # cache for discovery metadata documents
    lua_shared_dict jwks                  1m; # cache for JWKs
    lua_shared_dict introspection        10m; # cache for JWT verification results
```

插件本身提供了 init 方法。方便插件加载后做初始化动作。

注：如果部分插件的功能实现，需要在 Nginx 初始化启动，则可能需要在 __apisix.lua__ 文件的初始化方法 http_init 中添加逻辑，并且
    可能需要在 __bin/apisix__ 文件中，对 Nginx 配置文件生成的部分，添加一些你需要的处理。但是这样容易对全局产生影响，根据现有的
    插件机制，我们不建议这样做，除非你已经对代码完全掌握。

## 插件命名与配置

给插件取一个很棒的名字，确定插件的加载优先级，然后在 __conf/config.yaml__ 文件中添加上你的插件名。例如 key-auth 这个插件，
需要在代码里指定插件名称（名称是插件的唯一标识，不可重名），在 __apisix/plugins/key-auth.lua__ 文件中可以看到：

```lua
   local plugin_name = "key-auth"

   local _M = {
       version = 0.1,
       priority = 2500,
       type = 'auth',
       name = plugin_name,
       schema = schema,
   }
```

注：新插件的优先级（ priority 属性 ）不能与现有插件的优先级相同。另外，优先级( priority )值大的插件，会优先执行，比如 `basic-auth` 的优先级是 2520 ，`ip-restriction` 的优先级是 3000 ，所以在每个阶段，会先执行 `ip-restriction` 插件，再去执行 `basic-auth` 插件。

在 __conf/config.yaml__ 配置文件中，列出了启用的插件（都是以插件名指定的）：

```yaml
plugins:                          # plugin list
  - example-plugin
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
```

注：先后顺序与执行顺序无关。

特别需要注意的是，如果你的插件有新建自己的代码目录，那么就需要修改 Makefile 文件，新增创建文件夹的操作，比如：
```
$(INSTALL) -d $(INST_LUADIR)/apisix/plugins/skywalking
$(INSTALL) apisix/plugins/skywalking/*.lua $(INST_LUADIR)/apisix/plugins/skywalking/
```

## 配置描述与校验

定义插件的配置项，以及对应的 [Json Schema](https://json-schema.org) 描述，并完成对 json 的校验，这样方便对配置的数据规
格进行验证，以确保数据的完整性以及程序的健壮性。同样，我们以 key-auth 插件为例，看看他的配置数据：

```json
 "key-auth" : {
       "key" : "auth-one"
  }
```

插件的配置数据比较简单，只支持一个命名为 key 的属性，那么我们看下他的 Schema 描述：

```lua
   local schema = {
       type = "object",
       properties = {
           key = {type = "string"},
       }
   }
```

同时，需要实现 __check_schema(conf)__ 方法，完成配置参数的合法性校验。

```lua
   function _M.check_schema(conf)
       return core.schema.check(schema, conf)
   end
```

注：项目已经提供了 __core.schema.check__ 公共方法，直接使用即可完成配置参数校验。

## 确定执行阶段

根据业务功能，确定你的插件需要在哪个阶段执行。 key-auth 是一个认证插件，只要在请求进来之后业务响应之前完成认证即可。
该插件在 rewrite 、access 阶段执行都可以，项目中是用 rewrite 阶段执行认证逻辑，一般 IP 准入、接口权限是在 access 阶段
完成的。

## 编写执行逻辑

在对应的阶段方法里编写功能的逻辑代码。

## 编写测试用例

针对功能，完善各种维度的测试用例，对插件做个全方位的测试吧！插件的测试用例，都在 __t/plugin__ 目录下，可以前去了解。
项目测试框架采用的 [****test-nginx****](https://github.com/openresty/test-nginx)  。
一个测试用例 __.t__ 文件，通常用 \__DATA\__ 分割成 序言部分 和 数据部分。这里我们简单介绍下数据部分，
也就是真正测试用例的部分，仍然以 key-auth 插件为例：

```perl
=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.key-auth")
            local ok, err = plugin.check_schema({key = 'test-key'})
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

- 程序代码： Nginx  location 的配置内容
- 输入： http 的 request 信息
- 输出检查： status ，header ，body ，error_log 检查

这里请求 __/t__ ，经过配置文件 __location__ ，调用 __content_by_lua_block__ 指令完成 lua 的脚本，最终返回。
用例的断言是 response_body 返回 "done"，__no_error_log__ 表示会对 Nginx 的 error.log 检查，
必须没有 ERROR 级别的记录。

### 附上test-nginx 执行流程

根据我们在 Makefile 里配置的 PATH，和每一个 __.t__ 文件最前面的一些配置项，框架会组装成一个完整的 nginx.conf 文件，
__t/servroot__ 会被当成 Nginx 的工作目录，启动 Nginx 实例。根据测试用例提供的信息，发起 http 请求并检查 http 的返回项，
包括 http status，http response header， http response body 等。
