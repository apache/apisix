-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements.  See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership.  The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License.  You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing,
-- software distributed under the License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
-- KIND, either express or implied.  See the License for the
-- specific language governing permissions and limitations
-- under the License.

local core = require("apisix.core")
local consts = require("apisix.constants")
local new_redis_cli = require("apisix.utils.redis").new
local new_redis_cluster_cli = require("apisix.utils.rediscluster").new

local ngx_timer = ngx.timer
local redis_stop
local redis_cluster_stop
local _M = {}


local function sync_counter_data(premature, counter, to_be_synced, redis_confs, script)
  if premature then
    return
  end
  for key, _ in pairs(to_be_synced) do
    local num_reqs, err = counter:get(key .. consts.REDIS_COUNTER)
    if not num_reqs then
      core.log.error("failed to get num_reqs shdict during periodic sync: ", err)
      return
    end

    local conf = redis_confs[key]

    local red, err
    if conf.policy == "redis" then
      red, err = new_redis_cli(conf)
    elseif conf.policy == "redis-cluster" then
      red, err = new_redis_cluster_cli(conf)
    else
      core.log.error("invalid policy type: ", conf.policy)
      return
    end

    if not red then
      core.log.error("failed to get redis client during periodic sync: ", err)
      return
    end

    local res, err = red:eval(script, 1, key, conf.count, conf.time_window, num_reqs)
    if err then
      core.log.error("failed to sync shdict data to redis: ", err)
      return
    end

    local remaining = res[1]
    local ttl = res[2]
    core.log.info("syncing shdict num_req counter to redis. remaining: ", remaining,
                  " ttl: ", ttl, " reqs: ", num_reqs)
    counter:set(key .. consts.SHDICT_REDIS_REMAINING, tonumber(remaining), tonumber(ttl))
    counter:set(key .. consts.REDIS_COUNTER, 0)

    if (not redis_stop and (conf.policy == "redis"))
        or (not redis_cluster_stop and (conf.policy == "redis-cluster")) then
      local ok, err = ngx_timer.at(conf.sync_interval, sync_counter_data, counter, to_be_synced,
                                   redis_confs, script)
      if not ok then
        core.log.error("failed to create redis syncer timer: ", err,
                        ". New main redis syncer will be created.")

        -- next incoming request will pick this up and create a new timer
        counter:set(consts.REDIS_SYNCER, false)
      end
    end
  end
end

function _M.rate_limit_with_delayed_sync(conf, counter, to_be_synced, redis_confs, key, cost,
                                         limit, window, script)
  local syncer_started = counter:get(consts.REDIS_SYNCER)
  if not syncer_started then
    local ok, err = ngx_timer.at(conf.sync_interval, sync_counter_data, counter, to_be_synced,
                                 redis_confs, script)
    if ok then
      counter:set(consts.REDIS_SYNCER, true)
    else
      core.log.error("failed to create main redis syncer timer: ", err, ". Will retry next time.")
    end
  end

  to_be_synced[key] = true -- add to table for syncing
  redis_confs[key] = conf

  local incr, ierr = counter:incr(key .. consts.REDIS_COUNTER, cost, 1)
  if not incr then
    return nil, "failed to incr num req shdict: " .. ierr, 0
  end
  core.log.info("num reqs passed since sync to redis: ", incr)

  local ttl = 0
  local remaining, err = counter:incr(key .. consts.SHDICT_REDIS_REMAINING,
                                      0 - cost, limit, window)
  if not remaining then
    return nil, err, ttl
  end

  if remaining < 0 then
    return nil, "rejected", ttl
  end

  return 0, remaining, ttl
end


function _M.redis_syncer_stop()
  redis_stop = true
end


function _M.redis_cluster_syncer_stop()
  redis_cluster_stop = true
end


return _M
