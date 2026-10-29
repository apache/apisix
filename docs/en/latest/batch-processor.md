---
title: Batch Processor
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

The batch processor can be used to aggregate entries(logs/any data) and process them in a batch.
When the batch_max_size is set to 1 the processor will execute each entry immediately. Setting the batch max size more
than 1 will start aggregating the entries until it reaches the max size or the timeout expires.

## Configurations

The only mandatory parameter to create a batch processor is a function. The function will be executed when the batch reaches the max size
or when the buffer duration exceeds.

| Name             | Type    | Requirement | Default | Valid   | Description                                                  |
| ---------------- | ------- | ----------- | ------- | ------- | ------------------------------------------------------------ |
| name             | string  | optional    | logger's name | ["http logger",...] | A unique identifier used to identify the batch processor, which defaults to the name of the logger plug-in that calls the batch processor, such as plug-in "http logger" 's `name` is "http logger. |
| batch_max_size   | integer | optional    | 1000    | [1,...] | Sets the maximum number of logs sent in each batch. When the number of logs reaches the set maximum, all logs will be automatically pushed to the HTTP/HTTPS service. |
| inactive_timeout | integer | optional    | 5       | [1,...] | The maximum time to refresh the buffer (in seconds). When the maximum refresh time is reached, all logs will be automatically pushed to the HTTP/HTTPS service regardless of whether the number of logs in the buffer reaches the maximum number set. |
| buffer_duration  | integer | optional    | 60      | [1,...] | Maximum age in seconds of the oldest entry in a batch before the batch must be processed. |
| max_retry_count  | integer | optional    | 0       | [0,...] | Maximum number of retries before removing the entry from the processing pipeline when an error occurs. |
| retry_delay      | integer | optional    | 1       | [0,...] | Number of seconds the process execution should be delayed if the execution fails. |

## Limiting the backlog

Entries that have been buffered but not yet delivered are held in the worker's memory. When the log server is slow or unreachable, entries arrive faster than they leave and the backlog — along with the worker's memory — grows with the request rate.

Every logger built on the batch processor therefore accepts a `max_pending_entries` limit through its [plugin metadata](./terminology/plugin-metadata.md), which defaults to `8192`. While the backlog exceeds the limit, new entries are discarded and a summary is written to the error log at most once per second:

```text
max pending entries limit exceeded. discarding entry. total_pushed_entries: 12289 total_processed_entries: 4096 max_pending_entries: 8192 discarded_entries: 3172
```

The limit counts entries, so what it costs in memory depends on how large each entry is — above all on whether `include_req_body` and `include_resp_body` are enabled and how large those bodies are. The figures below are the peak growth in a worker's resident memory while its log server accepted connections but never answered, measured with `http-logger`, both bodies logged, and otherwise stock batch processor settings:

| Body logged per request | Peak worker memory at the default limit |
|-------------------------|-----------------------------------------|
| bodies not logged       | ~40 MB |
| 1 KB request + 1 KB response | ~100 MB |
| 4 KB request + 4 KB response | ~250 MB |
| 16 KB request + 16 KB response | ~840 MB |

The cost grows roughly in proportion to the body size, so lower `max_pending_entries` if you log bodies larger than a few KB. The figures are higher than the entries alone would account for because batches already handed to the sender hold both their entries and the serialized payload built from them.

The limit only comes into play when delivery falls behind. With a log server that keeps up, the backlog stays close to `batch_max_size` — under 1000 entries at 3000 requests per second in the same setup — so the default leaves about eight times the room healthy operation needs. Raising `batch_max_size` raises the healthy backlog with it, so raise `max_pending_entries` too if you do.

The following code shows an example of how to use batch processor in your plugin:

```lua
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
...

local plugin_name = "xxx-logger"
-- the second argument names the plugin whose metadata carries max_pending_entries,
-- and is only needed when the batch processor's own name differs from it
local batch_processor_manager = bp_manager_mod.new("xxx logger", plugin_name)
local schema = {...}
local metadata_schema = {...}
local _M = {
    ...
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    -- adds max_pending_entries to the plugin's metadata schema
    metadata_schema = batch_processor_manager:wrap_metadata_schema(metadata_schema),
}

...


function _M.log(conf, ctx)
    local entry = {...} -- data to log

    -- a true return means the entry needs nothing further from you: it was either
    -- pushed to an existing processor, or discarded because the backlog is over
    -- max_pending_entries
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

The batch processor's configuration will be set inside the plugin's configuration.
For example:

:::note
You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

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

If your plugin only uses one global batch processor,
you can also use the processor directly:

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

Note: Please make sure the batch max size (entry count) is within the limits of the function execution.
The timer to flush the batch runs based on the `inactive_timeout` configuration. Thus, for optimal usage,
keep the `inactive_timeout` smaller than the `buffer_duration`.
