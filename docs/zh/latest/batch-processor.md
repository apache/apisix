---
title: 批处理器
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

批处理器可用于聚合条目（日志/任何数据）并进行批处理。
当 `batch_max_size` 设置为 1 时，处理器将立即执行每个条目。将批处理的最大值设置为大于 1 将开始聚合条目，直到达到最大值或超时。

## 配置

创建批处理器的唯一必需参数是函数。当批处理达到最大值或缓冲区持续时间超过时，函数将被执行。

| 名称             | 类型    | 必选项 | 默认值 | 有效值  | 描述                                                         |
| ---------------- | ------- | ------ | ------ | ------- | ------------------------------------------------------------ |
| name             | string  | 可选   | xxx logger | ["http logger", "Some strings",...] | 用于标识批处理器的唯一标识符，默认为调用批处理器的日志插件名字，如配置插件为 `http logger`，name 默认为 http logger。  |
| batch_max_size   | integer | 可选   | 1000   | [1,...] | 设置每批发送日志的最大条数，当日志条数达到设置的最大值时，会自动推送全部日志到  HTTP/HTTPS 服务。 |
| inactive_timeout | integer | 可选   | 5      | [1,...] | 刷新缓冲区的最大时间（以秒为单位），当达到最大的刷新时间时，无论缓冲区中的日志数量是否达到设置的最大条数，也会自动将全部日志推送到  HTTP/HTTPS 服务。 |
| buffer_duration  | integer | 可选   | 60     | [1,...] | 必须先处理批次中最旧条目的最长期限（以秒为单位）。           |
| max_retry_count  | integer | 可选   | 0      | [0,...] | 从处理管道中移除之前的最大重试次数。                         |
| retry_delay      | integer | 可选   | 1      | [0,...] | 如果执行失败，则应延迟执行流程的秒数。                       |

## 限制积压条目数

已缓冲但尚未发送成功的条目保存在 worker 内存中。当日志服务变慢或不可达时，条目进入的速度快于离开的速度，积压量以及 worker 内存会随请求速率不断增长。

因此所有基于批处理器的日志插件都通过[插件元数据](./terminology/plugin-metadata.md)提供 `max_pending_entries` 上限，默认值为 `8192`。积压超过该上限期间新条目会被丢弃，并且每秒最多向错误日志输出一条汇总信息：

```text
max pending entries limit exceeded. discarding entry. total_pushed_entries: 12289 total_processed_entries: 4096 max_pending_entries: 8192 discarded_entries: 3172
```

该上限限制的是条目数量，因此实际占用多少内存取决于单条条目有多大——尤其取决于是否开启 `include_req_body` 和 `include_resp_body`，以及 body 的大小。下表是日志服务接受连接但始终不响应时 worker 常驻内存的峰值增长，测试使用 `http-logger`、同时收集请求和响应 body，批处理器其余配置保持默认：

| 每请求收集的 body | 默认上限下 worker 内存峰值 |
|-------------------|----------------------------|
| 不收集 body | ~40 MB |
| 1 KB 请求 + 1 KB 响应 | ~100 MB |
| 4 KB 请求 + 4 KB 响应 | ~250 MB |
| 16 KB 请求 + 16 KB 响应 | ~840 MB |

内存开销与 body 大小大致成正比，因此如果收集的 body 超过几 KB，应调低 `max_pending_entries`。表中数值高于条目本身的体积，是因为已经交给发送方的批次同时持有条目和由其序列化出的载荷。

只有在发送跟不上时该上限才会起作用。日志服务正常的情况下，积压量接近 `batch_max_size`——在相同环境下 3000 QPS 时不足 1000 条，因此默认值为正常运行留出了约 8 倍余量。调大 `batch_max_size` 会同步抬高正常状态下的积压量，此时也应相应调大 `max_pending_entries`。

以下代码显示了如何在你的插件中使用批处理器：

```lua
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
...

local plugin_name = "xxx-logger"
-- 第二个参数指定 max_pending_entries 所在的插件元数据名称，
-- 仅当批处理器自身的名称与插件名不同时才需要传入
local batch_processor_manager = bp_manager_mod.new("xxx logger", plugin_name)
local schema = {...}
local metadata_schema = {...}
local _M = {
    ...
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    -- 向插件的元数据 schema 中加入 max_pending_entries
    metadata_schema = batch_processor_manager:wrap_metadata_schema(metadata_schema),
}

...


function _M.log(conf, ctx)
    local entry = {...} -- data to log

    -- 返回 true 表示该条目已无需调用方再处理：要么已推入现有处理器，
    -- 要么因积压超过 max_pending_entries 而被丢弃
    if batch_processor_manager:add_entry(conf, entry) then
        return
    end
    -- create a new processor if not found

    -- entries is an array table of entry, which can be processed in batch
    local func = function(entries)
        -- serialize to json array core.json.encode(entries)
        -- process/send data
        return true
        -- return false, err_msg, first_fail if failed
        -- first_fail(optional) indicates first_fail-1 entries have been successfully processed
        -- and during processing of entries[first_fail], the error occurred. So the batch processor
        -- only retries for the entries having index >= first_fail as per the retry policy.
    end
    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end
```

批处理器的配置将通过该插件的配置设置。
举个例子：

:::note

您可以这样从 `config.yaml` 中获取 `admin_key` 并存入环境变量：

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/"//g')
```

:::

```shell
curl http://127.0.0.1:9180/apisix/admin/routes/1 -H "X-API-KEY: $admin_key" -X PUT -d '
{
      "plugins": {
            "http-logger": {
                "uri": "http://mockbin.org/bin/:ID",
                "batch_max_size": 10,
                "max_retry_count": 1
            }
       },
      "upstream": {
           "type": "roundrobin",
           "nodes": {
               "127.0.0.1:1980": 1
           }
      },
      "uri": "/hello"
}'
```

如果你的插件只使用一个全局的批处理器，
你可以直接使用它：

```lua
local entry = {...} -- data to log
if log_buffer then
    log_buffer:push(entry)
    return
end

local config_bat = {
    name = config.name,
    retry_delay = config.retry_delay,
    ...
}

local err
-- entries is an array table of entry, which can be processed in batch
local func = function(entries)
    ...
    return true
    -- return false, err_msg, first_fail if failed
end
log_buffer, err = batch_processor:new(func, config_bat)

if not log_buffer then
    core.log.warn("error when creating the batch processor: ", err)
    return
end

log_buffer:push(entry)
```

注意：请确保批处理的最大值（条目数）在函数执行的范围内。
刷新批处理的计时器基于 `inactive_timeout` 配置运行。因此，为了获得最佳使用效果，
保持 `inactive_timeout` 小于 `buffer_duration`。
