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

local popen = io.popen

local _M = {}


-- Note: The `execute_cmd` return value will have a line break at the end,
-- it is recommended to use the `trim` function to handle the return value.
function _M.execute_cmd(cmd)
    local t, err = popen(cmd)
    if not t then
        return nil, "failed to execute command: "
                    .. cmd .. ", error info: " .. err
    end

    local data, err = t:read("*all")
    t:close()

    if err ~= nil then
        return nil, "failed to read execution result of: "
                    .. cmd .. ", error info: " .. err
    end

    return data
end


function _M.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end


return _M
