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

# Batch Processor

The batch processor can be used to aggregate entries(logs/any data) and process them in a batch.
When the batch_max_size is set to zero the processor will execute each entry immediately. Setting the batch max size more
than 1 will start aggregating the entries until it reaches the max size or the timeout expires.


## Configurations

The only mandatory parameter to create a batch processor is a function. The function will be executed when the batch reaches the max size
or when the buffer duration exceeds.

|Name           |Requirement    |Description|
|-------        |-----          |------|
|id             |optional       |A unique identifier to identity the batch processor|
|batch_max_size |optional       |Max size of each batch, default is 1000|
|inactive_timeout|optional      |maximum age in seconds when the buffer will be flushed if inactive, default is 5s|
|buffer_duration|optional       |Maximum age in seconds of the oldest entry in a batch before the batch must be processed, default is 5|
|max_retry_count|optional       |Maximum number of retries before removing from the processing pipe line; default is zero|
|retry_delay    |optional       |Number of seconds the process execution should be delayed if the execution fails; default is 1|


The following code shows an example of how to use a batch processor. The batch processor takes a function to be executed as the first
argument and the batch configuration as the second parameter.


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

Note: Please make sure the batch max size (entry count) is within the limits of the function execution.
The timer to flush the batch runs based on the `inactive_timeout` configuration. Thus, for optimal usage,
keep the `inactive_timeout` smaller than the `buffer_duration`.
