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
local ipairs = ipairs
local pairs = pairs


local cmd_to_key_finder = {}
--[[
-- the data is generated from the script below
local redis = require "resty.redis"
local red = redis:new()

local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
    ngx.say("failed to connect: ", err)
    return
end

local res = red:command("info")
local map = {}
for _, r in ipairs(res) do
    local first_key = r[4]
    local last_key = r[5]
    local step = r[6]
    local idx = first_key .. ':' .. last_key .. ':' .. step

    if idx ~= "1:1:1" then
        -- "1:1:1" is the default
        if map[idx] then
            table.insert(map[idx], r[1])
        else
            map[idx] = {r[1]}
        end
    end
end
for _, r in pairs(map) do
    table.sort(r)
end
local dump = require('pl.pretty').dump; dump(map)
--]]
local key_to_cmd = {
    ["0:0:0"] = {
        "acl",
        "asking",
        "auth",
        "bgrewriteaof",
        "bgsave",
        "blmpop",
        "bzmpop",
        "client",
        "cluster",
        "command",
        "config",
        "dbsize",
        "debug",
        "discard",
        "echo",
        "eval",
        "eval_ro",
        "evalsha",
        "evalsha_ro",
        "exec",
        "failover",
        "fcall",
        "fcall_ro",
        "flushall",
        "flushdb",
        "function",
        "hello",
        "info",
        "keys",
        "lastsave",
        "latency",
        "lmpop",
        "lolwut",
        "memory",
        "module",
        "monitor",
        "multi",
        "object",
        "pfselftest",
        "ping",
        "psubscribe",
        "psync",
        "publish",
        "pubsub",
        "punsubscribe",
        "quit",
        "randomkey",
        "readonly",
        "readwrite",
        "replconf",
        "replicaof",
        "reset",
        "role",
        "save",
        "scan",
        "script",
        "select",
        "shutdown",
        "sintercard",
        "slaveof",
        "slowlog",
        "subscribe",
        "swapdb",
        "sync",
        "time",
        "unsubscribe",
        "unwatch",
        "wait",
        "xgroup",
        "xinfo",
        "xread",
        "xreadgroup",
        "zdiff",
        "zinter",
        "zintercard",
        "zmpop",
        "zunion"
    },
    ["1:-1:1"] = {
        "del",
        "exists",
        "mget",
        "pfcount",
        "pfmerge",
        "sdiff",
        "sdiffstore",
        "sinter",
        "sinterstore",
        "ssubscribe",
        "sunion",
        "sunionstore",
        "sunsubscribe",
        "touch",
        "unlink",
        "watch"
    },
    ["1:-1:2"] = {
        "mset",
        "msetnx"
    },
    ["1:-2:1"] = {
        "blpop",
        "brpop",
        "bzpopmax",
        "bzpopmin"
    },
    ["1:2:1"] = {
        "blmove",
        "brpoplpush",
        "copy",
        "geosearchstore",
        "lcs",
        "lmove",
        "rename",
        "renamenx",
        "rpoplpush",
        "smove",
        "zrangestore"
    },
    ["2:-1:1"] = {
        "bitop"
    },
    ["2:2:1"] = {
        "pfdebug"
    },
    ["3:3:1"] = {
        "migrate"
    }
}
local key_finders = {
    ["0:0:0"] = false,
    ["1:-1:1"] = function (idx, narg)
        return 1 < idx
    end,
    ["1:-1:2"] = function (idx, narg)
        return 1 < idx and idx % 2 == 0
    end,
    ["1:-2:1"] = function (idx, narg)
        return 1 < idx and idx < narg - 1
    end,
    ["1:2:1"] = function (idx, narg)
        return idx == 2 or idx == 3
    end,
    ["2:-1:1"] = function (idx, narg)
        return 2 < idx
    end,
    ["2:2:1"] = function (idx, narg)
        return idx == 3
    end,
    ["3:3:1"] = function (idx, narg)
        return idx == 4
    end
}
for k, cmds in pairs(key_to_cmd) do
    for _, cmd in ipairs(cmds) do
        cmd_to_key_finder[cmd] = key_finders[k]
    end
end


return {
    cmd_to_key_finder = cmd_to_key_finder,
    default_key_finder = function (idx, narg)
        return idx == 2
    end,
}
