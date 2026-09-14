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
local ngx = ngx

local ROLE_CLIENT = "client"
local ROLE_UPSTREAM = "upstream"
local CTX_KEY_CLIENT = "websocket_client"
local CTX_KEY_UPSTREAM = "websocket_upstream"

-- ngx.ctx is per-request and can only be accessed from within a request
-- context, so it must be fetched inside each wrapped function, not cached
-- as a module-level upvalue at require() time (which also runs during
-- init_by_lua, before any request exists).

local function wrap_stash_frame(key)
  return function(frame)
    ngx.ctx[key] = frame
  end
end


local function wrap_get_frame(key)
  return function()
    return ngx.ctx[key]
  end
end


local function wrap_set_frame_data(key)
  return function(data)
    ngx.ctx[key].payload = data
  end
end


local function wrap_set_status(key)
  return function(status)
    ngx.ctx[key].code = status
  end
end


local _M = {
  ROLE_CLIENT = ROLE_CLIENT,
  ROLE_UPSTREAM = ROLE_UPSTREAM,
  [ROLE_CLIENT] = {
    stash_frame = wrap_stash_frame(CTX_KEY_CLIENT),
    get_frame = wrap_get_frame(CTX_KEY_CLIENT),
    set_frame_data = wrap_set_frame_data(CTX_KEY_CLIENT),
    set_status = wrap_set_status(CTX_KEY_CLIENT),
    --drop_frame = wrap_drop_frame
  },
  [ROLE_UPSTREAM] = {
    stash_frame = wrap_stash_frame(CTX_KEY_UPSTREAM),
    get_frame = wrap_get_frame(CTX_KEY_UPSTREAM),
    set_frame_data = wrap_set_frame_data(CTX_KEY_UPSTREAM),
    set_status = wrap_set_status(CTX_KEY_UPSTREAM),
  },
}

function _M.get_role(role)
  if role == ROLE_CLIENT or role == "client" then
    return _M[ROLE_CLIENT]
  elseif role == ROLE_UPSTREAM or role == "upstream" then
    return _M[ROLE_UPSTREAM]
  else
    return nil, "invalid role: " .. tostring(role)
  end
end

return _M
