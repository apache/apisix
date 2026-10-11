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
local core = require("apisix.core")
local type = type

local _M = {}

_M.VERSION = "2.0"

-- JSON-RPC 2.0 standard error codes
_M.ERR_PARSE           = -32700
_M.ERR_INVALID_REQUEST = -32600
_M.ERR_METHOD_NOT_FOUND = -32601
_M.ERR_INVALID_PARAMS  = -32602
_M.ERR_INTERNAL        = -32603


-- The answer to any message that fails shape validation, as the MCP SDK gives it: always
-- a null id, always -32700, and a plain JSON body rather than an SSE frame --
-- even when the request did carry an id.
function _M.invalid_message()
    return {
        jsonrpc = _M.VERSION,
        error = {
            code = _M.ERR_PARSE,
            message = "Parse error: Invalid JSON-RPC message",
        },
        id = core.json.null,
    }
end


function _M.result(id, result)
    return { jsonrpc = _M.VERSION, id = id, result = result }
end


function _M.error(id, code, message, data)
    local err = { code = code, message = message }
    if data ~= nil then
        err.data = data
    end
    return { jsonrpc = _M.VERSION, id = id, error = err }
end


-- A JSON-RPC notification carries no id and must not be answered with a body.
function _M.is_notification(request)
    return type(request) == "table" and request.id == nil
end


-- Only the shape is checked here; whether the method exists is the server's
-- business. Callers answer a failure with invalid_message() and HTTP 400.
function _M.validate(request)
    if type(request) ~= "table" then
        return false
    end
    if request.jsonrpc ~= _M.VERSION then
        return false
    end
    if type(request.method) ~= "string" then
        return false
    end
    -- An explicit "id": null is not a valid request id; JSON-RPC reserves null
    -- for error responses. A missing id is a notification and stays legal.
    if request.id == core.json.null then
        return false
    end
    if request.params ~= nil then
        if type(request.params) ~= "table" then
            return false
        end
        -- MCP requires params to be an object; an array is rejected outright
        if request.params[1] ~= nil then
            return false
        end
    end
    return true
end


return _M
