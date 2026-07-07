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
local cjson = require("cjson")

local _M = {}


-- Parse a data-otlp.json file (one JSON object per line) into a spans_by_id table.
local function parse_spans(filepath)
    local file = io.open(filepath, "rb")
    if not file then
        return nil, "cannot open " .. filepath
    end

    local spans_by_id = {}
    for line in file:lines() do
        if line and #line > 0 then
            local ok, data = pcall(cjson.decode, line)
            if ok and data.resourceSpans then
                for _, rs in ipairs(data.resourceSpans) do
                    for _, ss in ipairs(rs.scopeSpans or {}) do
                        for _, span in ipairs(ss.spans or {}) do
                            spans_by_id[span.spanId] = span
                        end
                    end
                end
            end
        end
    end
    file:close()

    return spans_by_id
end


-- Find a child span of the given parent by name.
local function find_child(spans_by_id, parent_id, child_name)
    for _, span in pairs(spans_by_id) do
        if span.parentSpanId == parent_id and span.name == child_name then
            return span
        end
    end
    return nil
end


-- Convert span.attributes array into a key -> value map.
local function get_attr_map(span)
    local map = {}
    for _, attr in ipairs(span.attributes or {}) do
        local v = attr.value
        map[attr.key] = v.stringValue or v.intValue or v.boolValue
    end
    return map
end


-- Recursively verify a span tree node against the expected structure.
local function verify(spans_by_id, expected, actual, path, errors)
    if not actual then
        table.insert(errors, path .. ": span not found")
        return
    end

    if expected.kind and actual.kind ~= expected.kind then
        table.insert(errors, string.format(
            "%s: expected kind=%d, got=%s",
            path, expected.kind, tostring(actual.kind)))
    end

    if expected.attributes then
        local attr_map = get_attr_map(actual)
        for key, val in pairs(expected.attributes) do
            if tostring(attr_map[key]) ~= tostring(val) then
                table.insert(errors, string.format(
                    "%s: attr '%s' expected '%s', got '%s'",
                    path, key, tostring(val), tostring(attr_map[key])))
            end
        end
    end

    if expected.children then
        for _, child_exp in ipairs(expected.children) do
            local child = find_child(spans_by_id, actual.spanId, child_exp.name)
            verify(spans_by_id, child_exp, child,
                   path .. " > " .. child_exp.name, errors)
        end
    end
end


-- Main entry point: verify a span tree from a data-otlp.json file.
-- Returns true on success, or (false, error_string) on failure.
function _M.verify_tree(filepath, expected_tree)
    local spans_by_id, err = parse_spans(filepath)
    if not spans_by_id then
        return false, err
    end

    -- find root span (no parentSpanId)
    local root
    for _, span in pairs(spans_by_id) do
        if span.name == expected_tree.name
           and (not span.parentSpanId or span.parentSpanId == "")
        then
            root = span
            break
        end
    end

    local errors = {}
    verify(spans_by_id, expected_tree, root, expected_tree.name, errors)

    if #errors > 0 then
        return false, table.concat(errors, "\n")
    end
    return true
end


function _M.verify_isolated_traces(filepath, root_name, count, expected_names)
    local spans_by_id, err = parse_spans(filepath)
    if not spans_by_id then
        return false, err
    end

    local traces = {}
    for _, span in pairs(spans_by_id) do
        if not traces[span.traceId] then
            traces[span.traceId] = {}
        end
        table.insert(traces[span.traceId], span.name)
    end

    local matching = {}
    for trace_id, names in pairs(traces) do
        for _, name in ipairs(names) do
            if name == root_name then
                table.insert(matching, { id = trace_id, names = names })
                break
            end
        end
    end

    if #matching ~= count then
        return false, string.format(
            "expected %d traces with span '%s', got %d",
            count, root_name, #matching)
    end

    local expected_count = {}
    for _, name in ipairs(expected_names) do
        expected_count[name] = (expected_count[name] or 0) + 1
    end

    for _, trace in ipairs(matching) do
        local actual_count = {}
        for _, name in ipairs(trace.names) do
            actual_count[name] = (actual_count[name] or 0) + 1
        end

        for name, want in pairs(expected_count) do
            local got = actual_count[name] or 0
            if got ~= want then
                return false, string.format(
                    "trace %s: span '%s' expected %d time(s), got %d",
                    trace.id, name, want, got)
            end
        end

        for name, got in pairs(actual_count) do
            if not expected_count[name] then
                return false, string.format(
                    "trace %s: unexpected span '%s' (%d occurrence(s))",
                    trace.id, name, got)
            end
        end
    end

    return true
end


return _M
