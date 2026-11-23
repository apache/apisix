--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local limit_count = require("apisix.plugins.limit-count.init")
local workflow = require("apisix.plugins.workflow")
local limit_util = require("apisix.utils.limit")
local core = require("apisix.core")

local bucket_backend_fields = {
    redis = "$['redis_host','redis_port','redis_database']",
    ["redis-cluster"] = "$['redis_cluster_name','redis_cluster_nodes']",
    ["redis-sentinel"] = "$['redis_sentinels','redis_master_name','redis_database','redis_role']",
}

local plugin_name = "limit-count"
local _M = {
    version = 0.5,
    priority = 1002,
    name = plugin_name,
    schema = limit_count.schema,
    metadata_schema = limit_count.metadata_schema,
}


function _M.check_schema(conf, schema_type)
    local ok, err = limit_count.check_schema(conf, schema_type)
    if not ok or schema_type == core.schema.TYPE_METADATA then
        return ok, err
    end
    return limit_util.prepare_bucket_id(conf, {
        "$['key','key_type','time_window','window_type','group','policy']",
        "$.rules[*]['key','time_window']",
        "$._meta['filter','pre_function']",
        bucket_backend_fields[conf.policy],
    }, {"$.redis_cluster_nodes", "$.redis_sentinels"})
end


function _M.access(conf, ctx)
    return limit_count.rate_limit(conf, ctx, plugin_name, 1)
end

function _M.workflow_handler()
    workflow.register(plugin_name,
    function (conf)
        return limit_count.check_schema(conf)
    end,
    function (conf, ctx)
        return limit_count.rate_limit(conf, ctx, plugin_name, 1)
    end)
end

return _M
