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

--- Read secrets from files on the local file system, such as Kubernetes
--- Secrets mounted as a volume.
local core = require("apisix.core")

local sub = core.string.sub
local find = core.string.find

local schema = {
    type = "object",
    properties = {
        base_path = {
            type = "string",
            description = "absolute path of the directory that holds the secret files",
            pattern = [[^/]],
        },
    },
    required = {"base_path"},
}

local _M = {
    schema = schema
}


-- key is the path of the secret file, relative to base_path. For a mounted
-- Kubernetes Secret this is the key of the Secret, e.g. "password". A single
-- trailing newline is removed from the content, as most tools add one when
-- writing a file.
function _M.get(conf, key)
    core.log.info("fetching data from file for key: ", key)

    if key == "" or find(key, "/") == 1 then
        return nil, "can't find main key, key: " .. key
    end

    -- keep the key inside base_path
    if find("/" .. key .. "/", "/../") then
        return nil, "key must not contain '..' segments, key: " .. key
    end

    local base_path = conf.base_path
    if sub(base_path, -1) ~= "/" then
        base_path = base_path .. "/"
    end

    local path = base_path .. key
    local content, err = core.io.get_file(path)
    if not content then
        return nil, "failed to read secret file: " .. (err or path .. ": no content")
    end

    if sub(content, -2) == "\r\n" then
        content = sub(content, 1, -3)
    elseif sub(content, -1) == "\n" then
        content = sub(content, 1, -2)
    end

    if content == "" then
        return nil, "secret file is empty: " .. path
    end

    return content
end


return _M
