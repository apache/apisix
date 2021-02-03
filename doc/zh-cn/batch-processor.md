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

[English](../batch-processor.md)

# 批处理机

批处理处理器可用于聚合条目（日志/任何数据）并进行批处理。
当batch_max_size设置为零时，处理器将立即执行每个条目。将批处理的最大大小设置为大于1将开始聚合条目，直到达到最大大小或超时到期为止

## 构型

创建批处理程序的唯一必需参数是函数。当批处理达到最大大小或缓冲区持续时间超过时，将执行该功能。

|名称           |需求    |描述|
|-------        |-----          |------|
|id             |可选的       |标识批处理者的唯一标识符|
|batch_max_size |可选的       |每批的最大大小，默认为1000|
|inactive_timeout|可选的      |如果不活动，将刷新缓冲区的最大时间（以秒为单位），默认值为5s|
|buffer_duration|可选的       |必须先处理批次中最旧条目的最大期限（以秒为单位），默认是5|
|max_retry_count|可选的       |从处理管道中移除之前的最大重试次数；默认为零|
|retry_delay    |可选的       |如果执行失败，应该延迟进程执行的秒数；默认为1|

以下代码显示了如何使用批处理程序的示例。批处理处理器将要执行的功能作为第一个参数，将批处理配置作为第二个参数。

```lua
local bp = require("apisix.plugins.batch-processor")
local func_to_execute = function(entries)
            -- serialize to json array core.json.encode(entries)
            -- process/send data
            return true
       end

local config = {
    max_retry_count  = 2,
    buffer_duration  = 60,
    inactive_timeout  = 5,
    batch_max_size = 1,
    retry_delay  = 0
}


local batch_processor, err = bp:new(func_to_execute, config)

if batch_processor then
    batch_processor:push({hello='world'})
end
```

注意：请确保批处理的最大大小（条目数）在函数执行的范围内。
刷新批处理的计时器基于“ inactive_timeout”配置运行。因此，为了获得最佳使用效果，
保持“ inactive_timeout”小于“ buffer_duration”。
