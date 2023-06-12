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

--- I/O operations on files.
--
-- @module core.io

local open = io.open


local _M = {}

---
-- Read the contents of a file.
--
-- @function core.io.get_file
-- @tparam string file_name either an absolute path or
-- a relative path based on the APISIX working directory.
-- @treturn string The file content.
-- @usage
-- local file_content, err = core.io.get_file("conf/apisix.uid")
-- -- the `file_content` maybe the APISIX instance id in uuid format,
-- -- like "3f0e827b-5f26-440e-8074-c101c8eb0174"
function _M.get_file(file_name)
    local f, err = open(file_name, 'r')
    if not f then
        return nil, err
    end

    local req_body = f:read("*all")
    f:close()
    return req_body
end


return _M
