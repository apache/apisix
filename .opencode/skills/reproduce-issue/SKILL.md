---
name: apisix-reproduce-issue
description: 指导在完整 APISIX CI 环境中复现 issue 报告的问题。提供环境信息、可用服务列表和复现操作规范，确保复现过程可追溯、结果可验证。
license: Apache-2.0
compatibility: opencode
metadata:
  audience: contributors
  workflow: github
---

# 在 CI 环境中复现 APISIX Issue

## 目标

在 GitHub Actions CI 环境中，利用已搭建的完整 APISIX 运行环境，尝试复现上游 issue 报告的问题，并记录复现过程和结果。

## 当前环境信息

CI 环境已预装以下组件：

- **APISIX**: 基于 master 分支源码，已安装所有 Lua 依赖 (`make deps`)
- **OpenResty**: APISIX Runtime (自定义构建)，路径 `/usr/local/openresty/`
- **LuaJIT**: `/usr/local/openresty/luajit/bin/luajit`
- **LuaRocks**: 已安装并配置
- **etcd**: `3.5.4`，监听 `127.0.0.1:2379`
- **Redis**: 监听 `127.0.0.1:6379`
- **HashiCorp Vault**: 监听 `127.0.0.1:8200`（dev 模式，root token: `root`）
- **httpbin**: 监听 `127.0.0.1:8280`
- **Test::Nginx**: 已安装，test-nginx 库位于 `./test-nginx/`
- **Go**: `1.17`
- **Node.js**: LTS 版本

## APISIX 操作命令

```bash
# 初始化 APISIX（生成 nginx.conf + 初始化 etcd）
make init

# 启动 APISIX
make run
# 或
bin/apisix start

# 停止 APISIX
make stop
# 或
bin/apisix stop

# 重新加载配置
make reload
# 或
bin/apisix reload

# 查看 APISIX 版本
bin/apisix version

# 查看 OpenResty 版本
openresty -V
```

## Admin API

APISIX 启动后，Admin API 默认监听 `127.0.0.1:9180`，使用以下方式操作：

```bash
# 创建路由
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -X PUT -d '{
    "uri": "/test",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:8280": 1
      }
    }
  }'

# 查看路由
curl http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"

# 创建带插件的路由
curl -i http://127.0.0.1:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -X PUT -d '{
    "uri": "/test",
    "plugins": {
      "limit-count": {
        "count": 2,
        "time_window": 60,
        "rejected_code": 503
      }
    },
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "127.0.0.1:8280": 1
      }
    }
  }'
```

## 测试执行

```bash
# 运行特定测试文件
FLUSH_ETCD=1 prove --timer -Itest-nginx/lib -I./ -r t/plugin/limit-count.t

# 运行特定测试目录
FLUSH_ETCD=1 prove --timer -Itest-nginx/lib -I./ -r t/node/

# 运行所有测试（不建议在单次复现中使用）
make test
```

## 复现工作流

### 第一步：分析复现条件

从 issue 中提取：
- 触发问题所需的最小配置
- 请求方式和参数
- 预期行为和实际行为
- 涉及的 APISIX 版本（如果与当前 master 差异大，需注意）

### 第二步：准备环境

1. 确保 APISIX 已初始化和启动：
   ```bash
   make init && make run
   ```
2. 验证 APISIX 正常运行：
   ```bash
   curl -i http://127.0.0.1:9180/apisix/admin/routes -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"
   ```
3. 验证 etcd 连接：
   ```bash
   etcdctl endpoint health --endpoints=127.0.0.1:2379
   ```

### 第三步：执行复现

根据 issue 描述，选择以下方式之一：

**方式 A：通过 Admin API + curl 复现**
1. 使用 Admin API 创建相关路由/服务/上游/插件配置
2. 发送触发请求
3. 检查响应和错误日志

**方式 B：通过编写 Test::Nginx 测试复现**
1. 创建临时测试文件 `/tmp/reproduce.t`
2. 使用 `prove` 运行测试
3. 检查测试结果

**方式 C：通过修改配置文件复现**
1. 修改 `conf/config.yaml` 或创建 `conf/apisix.yaml`（standalone 模式）
2. 重新加载或重启 APISIX
3. 验证行为

### 第四步：检查日志

```bash
# 查看错误日志
tail -100 logs/error.log

# 查看访问日志
tail -100 logs/access.log

# 搜索特定错误
grep -i "error\|warn\|fatal" logs/error.log | tail -50
```

### 第五步：记录结果

复现结果必须包含：
- **复现状态**：`已复现` / `未复现` / `部分复现` / `环境不匹配无法复现`
- **复现步骤**：实际执行的命令和配置（完整可复制）
- **实际输出**：命令输出、HTTP 响应、日志片段
- **与 issue 描述的对比**：是否与报告一致
- **环境差异说明**：如果当前环境版本与 issue 报告版本不同，需注明

## 约束

- 不要修改 APISIX 源代码（仅修改配置文件和创建临时测试文件）
- 复现操作的所有临时文件放在 `/tmp/` 目录下
- 每个操作步骤都要记录完整的命令和输出
- 如果 issue 中缺少足够的复现信息，明确说明无法复现并列出缺失信息
- 复现结果为事实陈述，不做额外推断
