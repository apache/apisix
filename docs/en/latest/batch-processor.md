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

The following code shows an example of how to use batch processor in your plugin:

```lua
local bp_manager_mod = require("apisix.utils.batch-processor-manager")
...

local plugin_name = "xxx-logger"
local batch_processor_manager = bp_manager_mod.new(plugin_name)
local schema = {...}
local _M = {
    ...
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
}

...


function _M.log(conf, ctx)
    local entry = {...} -- data to log

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
