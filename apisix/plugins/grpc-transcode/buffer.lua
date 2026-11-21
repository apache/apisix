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

-- Exact, bounded unary-response accumulator. Never truncate and never forward
-- a partial protobuf or accidentally parse the first N bytes as a complete body.
local concat = table.concat
local M = {}
function M.push(ctx, chunk, eof, max_size)
    local state = ctx.grpc_transcode_buffer
    if not state then
        state = {bytes = 0, parts = {}}
        ctx.grpc_transcode_buffer = state
    end
    chunk = chunk or ""
    if state.bytes + #chunk > max_size then
        ctx.grpc_transcode_buffer = nil
        return nil, "response body exceeds max_resp_body_size"
    end
    state.bytes = state.bytes + #chunk
    if #chunk > 0 then
        state.parts[#state.parts + 1] = chunk
    end
    if not eof then return nil end
    ctx.grpc_transcode_buffer = nil
    return concat(state.parts)
end
return M
