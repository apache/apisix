local core = require("apisix.core")
local tab_insert = table.insert
local tab_concat = table.concat
local lrucache = core.lrucache.new({
    ttl = 300, count = 100
})


local schema = {
    type = "object",
    properties = {
        ret_code = {type = "integer", minimum = 200, default = 302},
        uri = {type = "string", minLength = 2},
    },
    required = {"uri"},
}


local plugin_name = "rewrite"

local _M = {
    version = 0.1,
    priority = 900,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function parse_uri(uri)
    local reg = [[\$\{([0-9a-zA-Z_]+)\} | \$([0-9a-zA-Z_]+) | ([^$]+)]]
    local iterator, err = ngx.re.gmatch(uri, reg, "jiox")
    if not iterator then
        return nil, err
    end

    local t = {}
    while true do
        local m, err = iterator()
        if err then
            return nil, err
        end

        if not m then
            break
        end

        tab_insert(t, m)
    end

    return t
end


local function concat_new_uri(uri, ctx)
    local pased_uri_segs, err = lrucache(uri, nil, parse_uri, uri)
    if not pased_uri_segs then
        return nil, err
    end

    local t = {}
    for _, uri_segs in ipairs(pased_uri_segs) do
        local pat1, pat2, plain_text = uri_segs[1], uri_segs[2], uri_segs[3]
        core.log.info(core.json.delay_encode(uri_segs))

        if pat1 then
            tab_insert(t, ctx.var[pat1])
        elseif pat2 then
            tab_insert(t, ctx.var[pat2])
        else
            tab_insert(t, plain_text)
        end
    end

    return tab_concat(t, "")
end


function _M.rewrite(conf, ctx)
    core.log.info("plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    local new_uri, err = concat_new_uri(conf.uri, ctx)
    if not new_uri then
        core.log.error("failed to genera new uri by: ", conf.uri, " error: ", 
                       err)
        core.response.exit(500)
    end

    core.response.set_header("Location", new_uri)
    core.response.exit(conf.ret_code)
end


return _M
