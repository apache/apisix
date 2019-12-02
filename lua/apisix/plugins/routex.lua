local core = require("apisix.core")
local typeof = require("typeof")
local log = require("apisix.core.log")
local ngx = ngx
local plugin_name = "routex"
local ipairs = ipairs
local re_match = ngx.re.match
local re_gmatch = ngx.re.gmatch
local decode_args = ngx.decode_args
local table_sort = table.sort
local str_sub = ngx.re.sub
local star = "\\*"
local uri_args = "uri-arg"
local path_reg = "path-reg"
local header = "header"
local default = "default"

local schema = {
    type = "array",
    items = {
        type = "object",
        properties = {
            matchs = {
                type = "array",
                items = {
                    type = "object",
                    properties = {
                        host = { type = "string"},
                        uri = { type = "string"},
                        use = {type = "string", enum = {uri_args, header, path_reg, default} },
                        key = {type = "string" },
                        values = {type = "array"},
                    }
                },
            },
            upstream = {type = "string"}, -- upstram_id
            priority = {type = "number"}, -- the bigger the Higher priority
        },
    }
}

local _M = {
    version = 0.1,
    priority = 900,
    name = plugin_name,
    schema = schema,
}

-- return bool
local function match_host(host, ctx)
    if host == "*" then
        return true
    else
        local h = re_match(ctx.var.host, host, 'jo')
        if h then
            return true
        end
    end
    return false
end

local function match_uri(uri, ctx)
    if uri == "*" or uri == "/*" then
        return true
    else
        local path = str_sub(uri, star, "",'jo')  -- remove '*'
        local u = re_match(ctx.var.uri, path, 'jo')
        if u then
            return true
        end
    end
    return false
end

local function has_value (tab, val)
    local tmp = val
    if typeof.table(val) then
        tmp = val[1]
    end
    for _, value in ipairs(tab) do
        if value == tmp then
            return true
        end
    end
    return false
end

local function match_args(key, values, ctx)
    local args_ctx = {}
    if ctx.var.args then
        args_ctx = decode_args(ctx.var.args)
    end
    if args_ctx and next(args_ctx) then
        if args_ctx[key] then
            if has_value(values, args_ctx[key]) then
                return true
            end
        else
            return false
        end
    else
        return false
    end
end

local function match_header(key, values, ctx)
    local headers = {}
    if ctx.headers then
        headers = ctx.headers
    end
    if headers and next(headers) then
        if headers[key] then
            if has_value(values, headers[key]) then
                return true
            end
        else
            return false
        end
    else
        return false
    end
end

local function match_regx(key, values, ctx)
    local uri = ctx.var.uri
    local t={}
    if uri then
        local iterator, err = re_gmatch(uri, key, "jo")
        while not err do
            local m, err = iterator()
            if err then
                log.error("path regular error: " .. core.json.encode(err))
                return
            end
            if not m then
                break
            end
            table.insert(t, m[1])
        end
    end
    if t and next(t) then
        if t[1] then
            if has_value(values, t[1]) then
                return true
            end
        else
            return false
        end
    else
        return false
    end
end

-- return bool
local function match(rules, ctx)
    -- host uri use key values
    for _, r in ipairs(rules) do
        -- host
        if not match_host(r.host, ctx) then
            return false
        end
        -- uri
        if not match_uri(r.uri, ctx) then
            return false
        end
        -- use
        if r.use == uri_args then
            -- querystring args
            if not match_args(r.key, r.values, ctx) then
                return false
            end
        elseif r.use == header then
            -- header
            if not match_header(r.key, r.values, ctx) then
                return false
            end
        elseif r.use == path_reg then
            -- path regx
            if not match_regx(r.key, r.values, ctx) then
                return false
            end
        elseif r.use == default then
            -- default
            -- do nothing
        else
            return false -- configuration error
        end
    end
    return true
end

local function sort_priority(a, b)
    return a.priority > b.priority
end

local function matchs(conf, ctx)
    if conf then
        -- sort
        table_sort(conf, sort_priority)
        -- match
        for _, s in ipairs(conf) do
            local is_match = match(s.matchs, ctx)
            if is_match then
                ctx.var.upstream_id = s.upstream
                break
            end
        end
    else
        log.info("nothing")
    end
end

-- rewrite phase distribute upstream
function _M.rewrite(conf, ctx)
    -- match higher priority rule
    matchs(conf, ctx)
end

return _M