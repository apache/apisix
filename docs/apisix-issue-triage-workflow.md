# APISIX Issue Triage (opencode + Notion) — n8n 工作流详细文档

## 1. 工作流概述

| 属性 | 值 |
|---|---|
| **名称** | APISIX Issue Triage (opencode + Notion) |
| **工作流 ID** | `zw2Y744mzNcZCFcY` |
| **标签** | `apisix-triage` |
| **状态** | 未激活 (`active: false`) |
| **节点总数** | 14 个 |
| **目标** | 自动从 GitHub `apache/apisix` 仓库拉取开放 Issue，利用 AI（opencode CLI）逐一分析分类，并将结果写入 Notion 数据库，形成可视化的 Issue 分诊看板 |

## 2. 流程总览（节点流转图）

```
┌──────────────────────────┐   ┌─────────────────────────────────┐
│ Manual Trigger (Full Sync)│   │ Schedule Trigger (Incremental)  │
│  (手动触发 - 全量模式)     │   │  (定时触发 - 每6小时增量)        │
└───────────┬──────────────┘   └──────────┬──────────────────────┘
            │                              │
            └──────────┬───────────────────┘
                       ▼
              ┌─────────────────┐
              │   Set Config    │
              │  (设置全局配置)   │
              └────────┬────────┘
                       ▼
            ┌──────────────────────┐
            │ Prepare Fetch Params │
            │ (计算时间窗口 since) │
            └──────────┬───────────┘
                       ▼
            ┌──────────────────────────┐
            │ GitHub: Get All Issues   │
            │ (获取所有开放 Issue)      │
            └──────────┬───────────────┘
                       ▼
       ┌───────────────────────────────────┐
       │ Normalize & Sort Issues           │
       │ (过滤PR、按创建时间升序、标准化)    │
       └───────────────┬───────────────────┘
                       ▼
              ┌─────────────────────┐
              │  Split In Batches   │◄──────────────────────────┐
              │  (分批处理)         │                            │
              └───┬───────────┬─────┘                           │
       完成分支 ↙            ↘ 每批处理                         │
  ┌────────────────┐    ┌──────────────────┐                    │
  │ All Done       │    │ Build opencode   │                    │
  │ Summary        │    │ Prompt           │                    │
  │ (最终统计汇总)  │    │ (构建AI分析命令) │                    │
  └────────────────┘    └────────┬─────────┘                    │
                                 ▼                              │
                     ┌─────────────────────────┐                │
                     │ Execute: opencode analyze│                │
                     │ (执行AI分析)             │                │
                     └───────────┬─────────────┘                │
                                 ▼                              │
                     ┌──────────────────────────┐               │
                     │ Parse opencode Result    │               │
                     │ (解析AI输出为结构化数据)  │               │
                     └───────────┬──────────────┘               │
                                 ▼                              │
                     ┌──────────────────────────┐               │
                     │ Upsert: Search & Decide  │               │
                     │ (查Notion是否已存在)      │               │
                     └───────────┬──────────────┘               │
                                 ▼                              │
                        ┌──────────────┐                        │
                        │  Is Update?  │                        │
                        └──┬────────┬──┘                        │
                  是(更新)↙         ↘否(新建)                   │
         ┌─────────────────┐  ┌──────────────────┐              │
         │ Notion: Update  │  │ Notion: Create   │              │
         │ Page            │  │ Page             │              │
         └────────┬────────┘  └────────┬─────────┘              │
                  └────────┬───────────┘                        │
                           ▼                                    │
                  ┌──────────────────┐                          │
                  │ Log Write Result │──────────────────────────┘
                  │ (记录写入结果)    │    (回到 Split In Batches
                  └──────────────────┘     处理下一批)
```

## 3. 各节点详细说明

### 3.1 触发器（两种入口）

#### 3.1.1 Manual Trigger (Full Sync) — 手动全量触发

- **类型**: `manualTrigger`
- **用途**: 需要对仓库中**所有**开放 Issue 进行全量分析时，手动点击执行
- **触发时**: 设置 `mode = "full"`，`since` 为 `1970-01-01T00:00:00Z`，不过滤任何时间范围

#### 3.1.2 Schedule Trigger (Incremental) — 定时增量触发

- **类型**: `scheduleTrigger`
- **执行频率**: 每 **6 小时** 自动执行一次
- **用途**: 增量模式，仅拉取近几小时内更新的 Issue
- **触发时**: 设置 `mode = "incremental"`

### 3.2 Set Config — 全局配置

| 配置项 | 值 | 说明 |
|---|---|---|
| `mode` | `full` 或 `incremental` | 由触发器决定，表达式判断 `Manual Trigger` 是否执行过 |
| `notion_database_id` | Notion 数据库 ID | 目标 Notion 数据库 |
| `notion_api_key` | Notion Integration Token | Notion API 认证密钥 |
| `incremental_hours` | `7` | 增量模式回溯时间窗口（小时），比定时间隔 6h 多 1h 以覆盖边界 |
| `batch_size` | `1` | 每批处理的 Issue 数量（当前为逐个处理） |

**模式判断逻辑**:

```javascript
mode = $('Manual Trigger (Full Sync)').isExecuted ? 'full' : 'incremental'
```

### 3.3 Prepare Fetch Params — 计算时间参数

- **类型**: Code 节点 (JavaScript)
- **职责**: 根据 `mode` 计算 `since` 时间戳
  - **增量模式**: `since = 当前时间 - incremental_hours(7h)`，仅拉取近期更新的 Issue
  - **全量模式**: `since = "1970-01-01T00:00:00Z"`，确保 GitHub API 不过滤任何 Issue
- **输出**: 在 config 对象中追加 `since` 字段

### 3.4 GitHub: Get All Issues — 拉取 GitHub Issue

- **类型**: GitHub 原生节点
- **仓库**: `apache/apisix`
- **过滤条件**: `state = "open"`（仅获取打开状态的 Issue）
- **分页**: `returnAll: true`（自动分页获取全部）
- **认证**: 使用预配置的 GitHub API 凭证

### 3.5 Normalize & Sort Issues (oldest first) — 标准化与排序

- **类型**: Code 节点 (JavaScript)
- **处理逻辑**:
  1. **过滤 PR**: 排除含 `pull_request` 字段的项（GitHub Issues API 会返回 PR）
  2. **按时间排序**: 按 `created_at` **升序**排列（最旧的 Issue 优先处理）
  3. **字段标准化**: 为每个 Issue 提取并重命名关键字段

- **输出字段**:

| 字段 | 说明 |
|---|---|
| `issue_number` | Issue 编号 |
| `issue_title` | Issue 标题 |
| `issue_url` | Issue 页面 URL |
| `issue_state` | 状态（open） |
| `issue_labels` | 已有标签（逗号分隔） |
| `issue_created_at` | 创建时间 |
| `issue_updated_at` | 最后更新时间 |
| `issue_author` | 作者 GitHub 用户名 |
| `issue_comments` | 评论数 |
| `notion_database_id` | 透传配置 |
| `notion_api_key` | 透传配置 |
| `batch_size` | 透传配置 |

### 3.6 Split In Batches — 分批处理

- **类型**: SplitInBatches 节点
- **批次大小**: 动态读取 `batch_size`（当前为 1，即逐条处理）
- **两个输出**:
  - **输出 0（完成）**: 所有批次处理完毕 → 进入 `All Done Summary`
  - **输出 1（当前批次）**: 当前批次的 Issue → 进入 `Build opencode Prompt`

### 3.7 Build opencode Prompt — 构建 AI 分析命令

- **类型**: Code 节点 (JavaScript)
- **职责**: 为每个 Issue 生成一条完整的 shell 命令，调用 `opencode` CLI 进行 AI 分析

**生成的 Prompt 模板**:

```
请分析 apache/apisix 仓库中的 Issue #<编号>。分析完成后请仅输出如下 JSON 格式：
{
  "issue_type": "bug|enhancement|feature-request|question|info-needed|invalid",
  "suggested_action": "close-no-response|close-question|close-invalid|request-info|add-label|assign-pr|needs-discussion|valid-bug-confirm",
  "priority": "P0-critical|P1-high|P2-medium|P3-low",
  "suggested_labels": ["label1", "label2"],
  "confidence": "high|medium|low",
  "summary": "一句话描述根本原因或功能需求（中文，50字以内）",
  "root_cause": "根本原因分析（中文，100字以内）",
  "next_action": "建议的下一步具体操作（中文，80字以内）"
}
```

**AI 输出字段说明**:

| 字段 | 类型 | 可选值 | 说明 |
|---|---|---|---|
| `issue_type` | string | `bug`, `enhancement`, `feature-request`, `question`, `info-needed`, `invalid` | Issue 类型分类 |
| `suggested_action` | string | `close-no-response`, `close-question`, `close-invalid`, `request-info`, `add-label`, `assign-pr`, `needs-discussion`, `valid-bug-confirm` | 建议的处置操作 |
| `priority` | string | `P0-critical`, `P1-high`, `P2-medium`, `P3-low` | 优先级判定 |
| `suggested_labels` | array | GitHub 标签名列表 | AI 建议添加的标签 |
| `confidence` | string | `high`, `medium`, `low` | AI 分析置信度 |
| `summary` | string | 中文，50字以内 | 一句话总结 |
| `root_cause` | string | 中文，100字以内 | 根本原因分析 |
| `next_action` | string | 中文，80字以内 | 建议的下一步操作 |

**命令构建方式**:

1. 将 prompt 文本进行 **Base64 编码**，避免 shell 特殊字符问题
2. 写入临时文件 `/tmp/opencode_prompt_<issue_number>_<timestamp>.txt`
3. 执行 `opencode run --title 'apisix-triage-<issue_number>' --format json` 命令
4. 使用 `tee` 将输出同时写入日志文件 `/tmp/opencode_<issue_number>.log`（可通过 `tail -f` 实时监控）
5. 捕获退出码，清理临时文件

**依赖**: 项目中的 opencode skill（`.opencode/skills/analyze-issue/SKILL.md`）提供 APISIX Issue 分析方法论指导

### 3.8 Execute: opencode analyze — 执行 AI 分析

- **类型**: Execute Command 节点
- **命令**: 执行上一步构建的 shell 命令
- **容错**: `continueOnFail: true`（即使命令失败也继续流程）
- **输出**: `stdout`（命令标准输出）和 `exitCode`（退出码）

### 3.9 Parse opencode Result — 解析 AI 分析结果

- **类型**: Code 节点 (JavaScript)
- **职责**: 将 opencode CLI 的输出解析为结构化数据

**解析策略（多层容错）**:

1. **NDJSON 事件流解析**: opencode 使用 `--format json` 输出 NDJSON 格式，每行一个 JSON 事件对象。提取所有 `type === "text"` 事件的 `part.text` 字段，拼接为 AI 回复全文
2. **Fallback**: 若 NDJSON 解析未得到文本，退回到原始 stdout 文本
3. **JSON 提取**: 使用正则 `/{[^{}]*(?:{[^{}]*}[^{}]*)*}/g` 匹配文本中的 JSON 对象，按长度降序排列，取第一个同时包含 `issue_type` 和 `summary` 字段的候选
4. **失败兜底**: 若全部解析失败，返回默认值：

| 默认字段 | 默认值 |
|---|---|
| `issue_type` | `unknown` |
| `suggested_action` | `needs-review` |
| `priority` | `P3-low` |
| `suggested_labels` | `[]` |
| `confidence` | `low` |
| `summary` | `opencode 解析失败，需人工检查` |
| `root_cause` | 空 |
| `next_action` | `人工审查` |

5. **退出码检查**: 非零退出码时在 `summary` 中标注 `opencode 退出码 <code>，需人工检查`

**输出**: 合并 Issue 原始信息 + AI 分析结果 + 时间戳 `analyzed_at`

### 3.10 Upsert: Search & Decide — Notion 去重查询

- **类型**: Code 节点 (JavaScript)，直接调用 Notion API
- **职责**: 在 Notion 数据库中查询是否已存在相同 `Issue Number` 的页面
- **容错**: `continueOnFail: true`，搜索失败时当作新建处理

**为什么不用原生 Notion 节点查询**: 原生节点在查询结果为 0 条时不输出任何 item，导致下游节点不执行、循环断裂。用 Code 节点通过 `$http` 调用 API 可以**始终返回 1 个 item**。

**查询逻辑**:

```
POST /v1/databases/<dbId>/query
filter: { property: "Issue Number", number: { equals: <issue_number> } }
page_size: 1
```

**输出**:

- `existing_page_id`: 已有页面 ID（若存在）或 `null`
- `is_update`: 布尔值，标识是更新还是新建

### 3.11 Is Update? — 条件路由

- **类型**: If 节点
- **条件**: `$json.is_update === true`
- **True 分支** → `Notion: Update Page`（更新已有页面）
- **False 分支** → `Notion: Create Page`（创建新页面）

### 3.12 Notion: Update Page / Notion: Create Page — 写入 Notion

两个节点功能相同，区别仅在于**更新已有页面** vs. **创建新页面**。

**写入的 Notion 数据库字段**:

| Notion 属性名 | 类型 | 数据来源 |
|---|---|---|
| Issue Title | Title | GitHub issue 标题 |
| Issue Number | Number | GitHub issue 编号 |
| Issue URL | URL | GitHub issue 链接 |
| Issue Type | Rich Text | AI 分析结果（bug/enhancement/feature-request/question/info-needed/invalid） |
| Suggested Action | Rich Text | AI 建议操作 |
| Priority | Rich Text | AI 判定优先级（P0~P3） |
| Suggested Labels | Rich Text | AI 建议标签（逗号分隔） |
| Existing Labels | Rich Text | GitHub 上已有标签 |
| Confidence | Rich Text | AI 分析置信度（high/medium/low） |
| Summary | Rich Text | AI 一句话总结（中文） |
| Root Cause | Rich Text | AI 根因分析（中文） |
| Next Action | Rich Text | AI 建议下一步操作（中文） |
| Author | Rich Text | Issue 作者 GitHub 用户名 |
| Comments Count | Number | Issue 评论数 |
| Issue Created At | Date | Issue 创建时间 |
| Issue Updated At | Date | Issue 最后更新时间 |
| Analyzed At | Date | AI 分析完成时间 |
| Status | Rich Text | 固定为 `"Pending"`（待人工审核） |

- **容错**: 两个节点均设置 `continueOnFail: true`

### 3.13 Log Write Result — 记录写入结果

- **类型**: Code 节点 (JavaScript)
- **职责**: 打印日志记录每条 Issue 的 Notion 写入结果
- **日志格式**: `[CREATE/UPDATE][OK/FAIL] Issue #<number> -> Notion page id=<id>`
- **输出**: `{ op, issue_number, notion_page_id, success }`
- **流转**: 输出回到 `Split In Batches` 节点，触发下一批处理（形成**循环**）

### 3.14 All Done Summary — 最终汇总统计

- **类型**: Code 节点 (JavaScript)
- **触发时机**: 所有批次处理完毕后执行
- **输出**: 汇总统计信息

| 字段 | 说明 |
|---|---|
| `total` | 处理总数 |
| `succeeded` | 成功数 |
| `failed` | 失败数 |
| `creates` | 新建数 |
| `updates` | 更新数 |
| `completed_at` | 完成时间 |

## 4. 数据流转生命周期

```
1. 触发 → 2. 配置初始化 → 3. 计算时间窗口
   → 4. 调用 GitHub API 获取 Issue 列表
   → 5. 过滤 PR + 按时间排序
   → 6. 进入分批循环 ──┐
      ┌────────────────┘
      │ 对每个 Issue:
      │   7. 构建 AI 分析 Prompt & Shell 命令
      │   8. 执行 opencode CLI 调用 AI 分析
      │   9. 解析 AI 输出为结构化 JSON
      │  10. 查询 Notion 判断新建/更新
      │  11. 写入 Notion 数据库
      │  12. 记录日志 → 回到步骤 6 处理下一个
      └────────────────┐
   → 13. 全部完成 → 输出汇总统计
```

## 5. 关键设计决策

1. **增量 vs 全量双模式**: 定时增量（6h 间隔 + 7h 窗口覆盖边界）避免重复全量扫描，同时保留手动全量触发能力
2. **batch_size = 1**: 逐条处理，确保 opencode AI 分析不会因并发过高导致超时或限流
3. **Base64 编码 Prompt**: 避免 Prompt 中的特殊字符（引号、换行、中文等）与 shell 语法冲突
4. **NDJSON 多层解析策略**: 兼容 opencode 的 JSON 事件流格式和普通文本格式，并有完善的 fallback 机制
5. **Upsert 机制**: 用 Code 节点替代原生 Notion 查询节点，解决零结果时循环断裂问题
6. **全链路 continueOnFail**: 关键节点（Execute Command、Notion 写入、Upsert 查询）均开启失败继续，保证单条失败不阻塞整体流程
7. **Status 固定为 "Pending"**: AI 分析结果仅作参考，所有 Issue 标记为待审核状态，最终由人工决策

## 6. 外部依赖

| 依赖 | 说明 |
|---|---|
| **GitHub API** | 通过 n8n GitHub 节点 + API 凭证访问 `apache/apisix` 仓库 |
| **opencode CLI** | 本地安装的 AI 编码工具，通过 `opencode run` 命令执行 Issue 分析 |
| **opencode skill** | 项目中配置的 `.opencode/skills/analyze-issue/SKILL.md`，为 AI 提供 APISIX Issue 分析方法论 |
| **Notion API** | 通过 n8n Notion 节点 + API Token 写入数据库 |

## 7. 日志与调试

- **实时监控**: 每个 Issue 分析时会将 opencode 输出写入 `/tmp/opencode_<issue_number>.log`，可通过 `tail -f /tmp/opencode_*.log` 实时查看
- **Prompt 临时文件**: `/tmp/opencode_prompt_<issue_number>_<timestamp>.txt`，分析完成后自动清理
- **n8n 控制台日志**: `Normalize & Sort Issues` 节点输出过滤后的 Issue 总数，`Log Write Result` 节点输出每条写入结果，`All Done Summary` 输出最终统计
