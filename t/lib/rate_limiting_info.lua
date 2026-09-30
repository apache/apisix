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
local cjson = require("cjson.safe")
local concat = table.concat

-- Logs the time-independent part of $rate_limiting_info as one line, and
-- checks the timestamps against each other instead of printing them.
local _M = {}


local function show(value)
    if value == nil then
        return "absent"
    end
    if value == cjson.null then
        return "null"
    end
    return tostring(value)
end


local function window_ok(info, window)
    local size = info.window_size_ms
    if window.end_ms - window.start_ms ~= size then
        return "bad-size"
    end
    if info.evaluated_at_ms < window.start_ms or info.evaluated_at_ms > window.end_ms then
        return "outside"
    end
    return "ok"
end


function _M.log()
    local raw = ngx.var.rate_limiting_info
    local info, err = cjson.decode(raw)
    if not info then
        ngx.log(ngx.ERR, "invalid rate_limiting_info: ", err, ": ", raw)
        return
    end

    local out = {
        info.window_type, info.decision,
        "cost=" .. show(info.cost),
    }

    local delayed = info.delayed_sync
    if type(delayed) == "table" then
        out[#out + 1] = "synced_count=" .. show(delayed.synced_count)
        out[#out + 1] = "local_delta=" .. show(delayed.local_delta)
        out[#out + 1] = "synced_at=" .. (delayed.synced_at_ms <= info.evaluated_at_ms
                                          and "ok" or "later")
    end

    local cur = info.current_window
    if type(cur) ~= "table" then
        out[#out + 1] = "current_window=" .. show(cur)
        ngx.log(ngx.WARN, "rate limiting info: ", concat(out, " "))
        return
    end

    out[#out + 1] = "count=" .. show(cur.count)
    if info.window_type == "fixed" then
        out[#out + 1] = "created=" .. show(cur.created)
        out[#out + 1] = "window=" .. window_ok(info, cur)
        if cur.created == true and cur.start_ms ~= info.evaluated_at_ms then
            out[#out + 1] = "created-not-at-start"
        end
        out[#out + 1] = "previous_window=" .. show(info.previous_window)
    else
        out[#out + 1] = "window=" .. window_ok(info, cur)
        if cur.start_ms ~= cur.id * info.window_size_ms then
            out[#out + 1] = "not-aligned"
        end
        local prev = info.previous_window
        out[#out + 1] = "previous_count=" .. show(prev.count)
        local weight = prev.weight
        if weight < 0 or weight > 1
           or math.abs(prev.weighted_count - prev.count * weight) > 0.001 then
            out[#out + 1] = "bad-weight"
        end
    end

    ngx.log(ngx.WARN, "rate limiting info: ", concat(out, " "))
end


return _M
