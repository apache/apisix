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

-- One outbound request with a bound on how much of the response is read.
-- request_uri() buffers whatever the other end sends, which neither the tool
-- call nor the document fetch can afford: both talk to a host the route's
-- configuration, or the document itself, chose.
local core         = require("apisix.core")
local http         = require("resty.http")
local type         = type
local tostring     = tostring
local str_find     = string.find
local tonumber     = tonumber
local table_concat = table.concat

local _M = {}

local READ_SIZE = 64 * 1024


-- Returns a response table {status, reason, headers, body}, or nil plus an
-- error. `truncated` is true when the body stopped at max_body_size, in which
-- case body is nil: a partial document or payload is not worth returning.
function _M.request(url, opts)
    opts = opts or {}

    local httpc, client_err = http.new()
    if not httpc then
        return nil, "failed to create http client: " .. tostring(client_err)
    end
    httpc:set_timeout(opts.timeout)

    -- query_in_path = false: parsed[4] is the path, parsed[5] the query string.
    -- They have to stay apart, because the client rejects a "?" inside a path.
    local parsed, parse_err = httpc:parse_uri(url, false)
    if not parsed then
        return nil, tostring(parse_err)
    end

    local scheme, host, port = parsed[1], parsed[2], parsed[3]
    local ok, conn_err = httpc:connect({
        scheme = scheme,
        host = host,
        port = port,
        ssl_server_name = host,
    })
    if not ok then
        return nil, tostring(conn_err)
    end

    -- Host is left to the client: it appends the port when it is not the
    -- default one for the scheme, which a vhost-routed backend needs.
    local res, req_err = httpc:request({
        method = opts.method or "GET",
        path = parsed[4],
        query = parsed[5],
        headers = opts.headers,
        body = opts.body,
    })
    if not res then
        httpc:close()
        return nil, tostring(req_err)
    end

    -- A body with neither Content-Length nor chunked encoding ends when the
    -- connection does, and the reader reports that as "closed" alongside the
    -- last piece of it. That is the end of a complete body, not a failure.
    --
    -- What counts as chunked is the client's own predicate: it picks the
    -- chunked reader only for "Transfer-Encoding: chunked", so a body sent as
    -- "identity", or with any other transfer coding, is read to the close like
    -- one with no framing at all. A Content-Length that is there but not
    -- reached is the one case where a close really is a truncated body.
    --
    -- The client also requires HTTP/1.1 for that, and the response does not
    -- carry its version, so a chunked body on an HTTP/1.0 response is read to
    -- the close and reported here as an error. Chunked is not part of
    -- HTTP/1.0; refusing that response is the intended reading.
    local content_length = tonumber(res.headers["Content-Length"])
    local chunked = http.transfer_encoding_is_chunked(res.headers)
    local limit = opts.max_body_size
    local reader = res.body_reader
    local chunks, read_bytes = {}, 0

    while reader do
        local chunk, read_err = reader(READ_SIZE)
        if chunk then
            read_bytes = read_bytes + #chunk
            if limit and read_bytes > limit then
                httpc:close()
                return { status = res.status, reason = res.reason,
                         headers = res.headers, truncated = true }
            end
            chunks[#chunks + 1] = chunk
        end

        if read_err then
            if read_err == "closed" and not chunked
               and (not content_length or read_bytes >= content_length)
            then
                break
            end
            httpc:close()
            return nil, tostring(read_err)
        end

        if not chunk then
            break
        end
    end

    local keepalive_ok, keepalive_err = httpc:set_keepalive()
    if not keepalive_ok then
        core.log.info("failed to keep the connection alive: ", keepalive_err)
    end

    return {
        status = res.status,
        reason = res.reason,
        headers = res.headers,
        body = table_concat(chunks),
    }
end


-- The names and values a tool call contributes are checked, because
-- resty.http writes "<name>: <value>\r\n" as given: a newline in either would
-- let the caller append headers, or a whole request, to the one being sent.
-- The route's own headers go through this too -- they are templates resolved
-- against the request, so their values are not fixed either.
function _M.header_is_sane(name, value)
    if type(name) ~= "string" or name == "" then
        return false
    end
    -- core.string.find is a plain search; these are patterns, so they need
    -- string.find itself
    if str_find(name, "[%s:]") then
        return false
    end
    return not str_find(tostring(value), "[\r\n]")
end


return _M
