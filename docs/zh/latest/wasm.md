# Wasm

APISIX 支持使用 [Proxy Wasm SDK](https://github.com/proxy-wasm/spec#sdks) 编写的 Wasm 插件。

目前，仅实现了少数 API。请关注 [wasm-nginx-module](https://github.com/api7/wasm-nginx-module) 以了解进展。

## 编程模型

所有插件都在同一个 Wasm VM 中运行，就像 Lua 插件在 Lua VM 中一样。

每个插件都有自己的 VMContext（根 ctx）。

每个配置的路由/全局规则都有自己的 PluginContext（插件 ctx）。例如，如果我们有一个配置了 Wasm 插件的服务，并且有两个路由继承自它，将会有两个插件 ctx。

每个命中该配置的 HTTP 请求都有自己的 HttpContext（HTTP ctx）。例如，如果我们同时配置了全局规则和路由，HTTP 请求将有两个 HTTP ctx，一个用于来自全局规则的插件 ctx，另一个用于来自路由的插件 ctx。

## 如何使用

首先，我们需要在`config.yaml`中定义插件：

```yaml
wasm:
  plugins:
    - name: wasm_log # 插件的名称
      priority: 7999 # 优先级
      file: t/wasm/log/main.go.wasm # `.wasm` 文件的路径
      http_request_phase: access # 默认是"access"，可以是["access", "rewrite"]之一
```

就是这样。现在您可以像使用常规插件一样使用 Wasm 插件。

例如，在指定路由上启用此插件：

**注意**

您可以从`config.yaml`中获取`<beginning of the code>admin_key<end of the code>`，并使用以下命令将其保存到环境变量中：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed's/"//g')
```

然后执行以下命令：

```bash
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
    "uri": "/index.html",
    "plugins": {
        "wasm_log": {
            "conf": "blahblah"
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

以下是插件中可以配置的属性：

|名称 | 类型 | 要求 | 默认 | 有效 | 描述|
|---|---|---|---|---|---|
|conf|字符串或结构体 | 必填 | 无 | 不得为空 |插件 ctx 配置，可以通过 Proxy Wasm SDK 获取|

这里是 Proxy Wasm 回调与 APISIX 阶段的映射：

- `proxy_on_configure`：在新配置没有 PluginContext 时运行一次。例如，当第一个请求命中配置了 Wasm 插件的路由时。
- `proxy_on_http_request_headers`：在 access/rewrite 阶段运行，具体取决于`http_request_phase`的配置。
- `proxy_on_http_request_body`：在与`proxy_on_http_request_headers`相同的阶段运行。要运行此回调，我们需要在`proxy_on_http_request_headers`中将属性`wasm_process_req_body`设置为非空值。请参考`t/wasm/request-body/main.go`作为示例。
- `proxy_on_http_response_headers`：在 header_filter 阶段运行。
- `proxy_on_http_response_body`：在 body_filter 阶段运行。要运行此回调，我们需要在`proxy_on_http_response_headers`中将属性`wasm_process_resp_body`设置为非空值。请参考`t/wasm/response-rewrite/main.go`作为示例。

## 示例

我们在这个仓库的`t/wasm/`下重新实现了一些 Lua 插件：

- fault - injection
- forward - auth
- response - rewrite
- Slack
- Twitter
